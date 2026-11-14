#include "engine_cuda.h"

#include "extensions/engine_extension.h"
#include "tools/array_ops.h"

#include <cooperative_groups.h>

#include <algorithm>
#include <stdexcept>
#include <string>
#include <vector>
#include <cstdlib>
#include <cmath>

#define CUDA_CHECK(call) \
	do { \
		cudaError_t err_ = (call); \
		if (err_ != cudaSuccess) \
			throw std::runtime_error(std::string("CUDA error: ") + cudaGetErrorString(err_) \
				+ " (" + __FILE__ + ":" + std::to_string(__LINE__) + ")"); \
	} while (0)

static inline unsigned int DivCeil(unsigned int a, unsigned int b) { return (a + b - 1) / b; }

//! \brief construct an Engine instance
//! it's the responsibility of the caller to free the returned pointer
Engine_CUDA* Engine_CUDA::New(const Operator_CUDA* op, unsigned int cuda_device_number)
{
	cout << "Create FDTD engine (CUDA)" << endl;
	Engine_CUDA* e = new Engine_CUDA(op);
	e->setCUDAdevice(cuda_device_number);
	try
	{
		e->Init();
	}
	catch (...)
	{
		delete e; // frees what Init() has allocated so far
		throw;
	}
	return e;
}

Engine_CUDA::Engine_CUDA(const Operator_CUDA* op) : Engine::Engine(op)
{
	m_cuda_device_number = 0;
	m_supports_coop_launch = 0;
	m_gridDim = dim3(0, 0, 0);
	m_blockDim = dim3(0, 0, 0);
	m_numCells = 0;
	d_volt = d_curr = d_vv = d_vi = d_ii = d_iv = NULL;
	m_host_stale = false;
	m_device_stale = false;
	m_pointReads = 0;
	m_pointReadLimit = 8;
	d_partial = NULL;
	m_numPartial = 0;
	Op = op;
	m_type = CUDA;
}

void Engine_CUDA::setCUDAdevice(unsigned int cuda_device_number) {
	m_cuda_device_number = cuda_device_number;
}

static float4* AllocDevice(size_t bytes, const char* what)
{
	float4* p = NULL;
	cudaError_t err = cudaMalloc((void**)&p, bytes);
	if (err != cudaSuccess)
		throw std::runtime_error(std::string("CUDA engine: cannot allocate ") + std::to_string(bytes >> 20)
			+ " MB of GPU memory for " + what + ": " + cudaGetErrorString(err));
	return p;
}

void Engine_CUDA::Init()
{
	int nDevices = 0;
	CUDA_CHECK(cudaGetDeviceCount(&nDevices));
	if (nDevices <= 0)
		throw std::runtime_error("No CUDA devices found");
	if (m_cuda_device_number >= (unsigned int)nDevices)
		throw std::runtime_error("CUDA device number out of range");

	cudaDeviceProp prop;
	CUDA_CHECK(cudaGetDeviceProperties(&prop, m_cuda_device_number));
	cout << "  Running on device: " << prop.name << endl;

	CUDA_CHECK(cudaSetDevice(m_cuda_device_number));
	CUDA_CHECK(cudaDeviceGetAttribute(&m_supports_coop_launch, cudaDevAttrCooperativeLaunch, m_cuda_device_number));

	if (numLines[0] == 0 || numLines[1] == 0 || numLines[2] == 0)
		throw std::runtime_error("CUDA engine: empty FDTD grid");

	// threadIdx.x runs along z, the fastest changing index in memory, so that
	// neighbouring threads access neighbouring float4 values (coalesced access)
	m_blockDim = dim3(32, 4, 2);
	m_gridDim = dim3(
		DivCeil(numLines[2], m_blockDim.x),
		DivCeil(numLines[1], m_blockDim.y),
		DivCeil(numLines[0], m_blockDim.z)
	);
	if (m_gridDim.y > 65535 || m_gridDim.z > 65535)
		throw std::runtime_error("CUDA engine: FDTD grid too large for the kernel launch configuration");

	cout << "numLines: " << numLines[0] << ", " << numLines[1] << ", " << numLines[2] << endl;
	cout << "grid dim: " << m_gridDim.x << ", " << m_gridDim.y << ", " << m_gridDim.z
	     << "  block dim: " << m_blockDim.x << ", " << m_blockDim.y << ", " << m_blockDim.z << endl;

	numTS = 0;
	m_numCells = (size_t)numLines[0] * numLines[1] * numLines[2];
	const size_t bytes = m_numCells * sizeof(float4);

	if (Op->m_vv.size() != m_numCells || Op->m_vi.size() != m_numCells
		|| Op->m_ii.size() != m_numCells || Op->m_iv.size() != m_numCells)
		throw std::runtime_error("CUDA engine: operator arrays do not match the FDTD grid");

	FreeDevice();
	d_volt = AllocDevice(bytes, "voltages");
	d_curr = AllocDevice(bytes, "currents");
	d_vv = AllocDevice(bytes, "operator vv");
	d_vi = AllocDevice(bytes, "operator vi");
	d_ii = AllocDevice(bytes, "operator ii");
	d_iv = AllocDevice(bytes, "operator iv");

	CUDA_CHECK(cudaMemset(d_volt, 0, bytes));
	CUDA_CHECK(cudaMemset(d_curr, 0, bytes));
	// the operator is complete now: one upload, it is not touched again during the simulation
	CUDA_CHECK(cudaMemcpy(d_vv, Op->m_vv.data(), bytes, cudaMemcpyHostToDevice));
	CUDA_CHECK(cudaMemcpy(d_vi, Op->m_vi.data(), bytes, cudaMemcpyHostToDevice));
	CUDA_CHECK(cudaMemcpy(d_ii, Op->m_ii.data(), bytes, cudaMemcpyHostToDevice));
	CUDA_CHECK(cudaMemcpy(d_iv, Op->m_iv.data(), bytes, cudaMemcpyHostToDevice));

	const float4 zero = {0.0f, 0.0f, 0.0f, 0.0f};
	m_h_volt.assign(m_numCells, zero);
	m_h_curr.assign(m_numCells, zero);
	// one single-value read costs about as much as 160 kB of transfer: that many reads equal a full download
	m_pointReadLimit = 4 + (unsigned int)std::min<size_t>((2 * bytes) / 160000, 1000000);
	m_pointReads = 0;
	m_host_stale = false;
	m_device_stale = false;

	cout << "  GPU memory for fields and operator: " << ((6 * bytes) >> 20) << " MB, host mirror of the fields: "
	     << ((2 * bytes) >> 20) << " MB" << endl;

	const char* selftest = getenv("OPENEMS_CUDA_SELFTEST");
	if (selftest && atoi(selftest) > 0)
		SelfTest((unsigned int)atoi(selftest));

	InitExtensions();
	SortExtensionByPriority();

	// GPU extensions work directly on the GPU arrays, the others on the host mirror of the fields
	// (correct, but every use of the fields by such an extension copies them between GPU and host)
	for (size_t n = 0; n < m_Eng_exts.size(); ++n)
	{
		const std::string name = m_Eng_exts.at(n)->GetExtensionName();
		const bool onGpu = (name.find("(GPU)") != std::string::npos);
		cout << (onGpu ? "  Extension runs on the GPU: " : "  Extension runs on the host (slow): ") << name << endl;
	}
}

Engine_CUDA::~Engine_CUDA()
{
	// Engine::~Engine() only reaches Engine::Reset(), so free the CUDA arrays here
	Reset();
}

void Engine_CUDA::FreeDevice()
{
	cudaSetDevice(m_cuda_device_number);
	if (d_partial)
		cudaFree(d_partial);
	d_partial = NULL;
	m_numPartial = 0;
	float4** ptrs[] = {&d_volt, &d_curr, &d_vv, &d_vi, &d_ii, &d_iv};
	for (size_t n = 0; n < sizeof(ptrs) / sizeof(ptrs[0]); ++n)
	{
		if (*ptrs[n])
			cudaFree(*ptrs[n]);
		*ptrs[n] = NULL;
	}
}

void Engine_CUDA::Reset()
{
	FreeDevice();
	std::vector<float4>().swap(m_h_volt);
	std::vector<float4>().swap(m_h_curr);
	m_host_stale = false;
	m_device_stale = false;

	ClearExtensions();
}

void Engine_CUDA::SyncToHost() const
{
	if (!m_host_stale)
		return;
	const size_t bytes = m_numCells * sizeof(float4);
	CUDA_CHECK(cudaSetDevice(m_cuda_device_number));
	CUDA_CHECK(cudaMemcpy(m_h_volt.data(), d_volt, bytes, cudaMemcpyDeviceToHost));
	CUDA_CHECK(cudaMemcpy(m_h_curr.data(), d_curr, bytes, cudaMemcpyDeviceToHost));
	m_host_stale = false;
}

void Engine_CUDA::SyncToDevice()
{
	if (!m_device_stale)
		return;
	const size_t bytes = m_numCells * sizeof(float4);
	CUDA_CHECK(cudaSetDevice(m_cuda_device_number));
	CUDA_CHECK(cudaMemcpy(d_volt, m_h_volt.data(), bytes, cudaMemcpyHostToDevice));
	CUDA_CHECK(cudaMemcpy(d_curr, m_h_curr.data(), bytes, cudaMemcpyHostToDevice));
	m_device_stale = false;
}

// threadIdx.x -> z, threadIdx.y -> y, threadIdx.z -> x
__global__ void VoltageKernel(float4* __restrict__ volt, const float4* __restrict__ curr,
                              const float4* __restrict__ vi, const float4* __restrict__ vv,
                              unsigned int Nx, unsigned int Ny, unsigned int Nz)
{
	const unsigned int z = blockIdx.x * blockDim.x + threadIdx.x;
	const unsigned int y = blockIdx.y * blockDim.y + threadIdx.y;
	const unsigned int x = blockIdx.z * blockDim.z + threadIdx.z;

	if (x >= Nx || y >= Ny || z >= Nz) return;

	const size_t strideX = (size_t)Ny * Nz;
	const size_t strideY = Nz;
	const size_t k = (size_t)x * strideX + (size_t)y * strideY + z;

	const float4 i  = curr[k];
	const float4 ix = curr[x ? k - strideX : k];
	const float4 iy = curr[y ? k - strideY : k];
	const float4 iz = curr[z ? k - 1 : k];
	const float4 vvk = vv[k];
	const float4 vik = vi[k];
	float4 v = volt[k];

	v.x = v.x * vvk.x + vik.x * (i.z - iy.z - i.y + iz.y);
	v.y = v.y * vvk.y + vik.y * (i.x - iz.x - i.z + ix.z);
	v.z = v.z * vvk.z + vik.z * (i.y - ix.y - i.x + iy.x);

	volt[k] = v;
}

__global__ void CurrentKernel(const float4* __restrict__ volt, float4* __restrict__ curr,
                              const float4* __restrict__ iv, const float4* __restrict__ ii,
                              unsigned int Nx, unsigned int Ny, unsigned int Nz)
{
	const unsigned int z = blockIdx.x * blockDim.x + threadIdx.x;
	const unsigned int y = blockIdx.y * blockDim.y + threadIdx.y;
	const unsigned int x = blockIdx.z * blockDim.z + threadIdx.z;

	// the last line in every direction has no upper neighbour and is not updated
	if (x + 1 >= Nx || y + 1 >= Ny || z + 1 >= Nz) return;

	const size_t strideX = (size_t)Ny * Nz;
	const size_t strideY = Nz;
	const size_t k = (size_t)x * strideX + (size_t)y * strideY + z;

	const float4 v  = volt[k];
	const float4 vx = volt[k + strideX];
	const float4 vy = volt[k + strideY];
	const float4 vz = volt[k + 1];
	const float4 ivk = iv[k];
	const float4 iik = ii[k];
	float4 i = curr[k];

	i.x = i.x * iik.x + ivk.x * (v.z - vy.z - v.y + vz.y);
	i.y = i.y * iik.y + ivk.y * (v.x - vz.x - v.z + vx.z);
	i.z = i.z * iik.z + ivk.z * (v.y - vx.y - v.x + vy.x);

	curr[k] = i;
}

void Engine_CUDA::RunVoltageKernel()
{
	SyncToDevice(); // an extension may have changed the fields on the host
	VoltageKernel<<<m_gridDim, m_blockDim>>>(d_volt, d_curr, d_vi, d_vv, numLines[0], numLines[1], numLines[2]);
	CUDA_CHECK(cudaGetLastError());
	MarkHostStale(); // the host mirror is outdated until the next Get/Set call
}

void Engine_CUDA::RunCurrentKernel()
{
	SyncToDevice();
	CurrentKernel<<<m_gridDim, m_blockDim>>>(d_volt, d_curr, d_iv, d_ii, numLines[0], numLines[1], numLines[2]);
	CUDA_CHECK(cudaGetLastError());
	MarkHostStale();
}

// block reduction of the field energy: one double2 (E, H) per block
__global__ void EnergyKernel(const float4* __restrict__ volt, const float4* __restrict__ curr,
                             unsigned int Nx, unsigned int Ny, unsigned int Nz, double2* __restrict__ partial)
{
	const unsigned int z = blockIdx.x * blockDim.x + threadIdx.x;
	const unsigned int y = blockIdx.y * blockDim.y + threadIdx.y;
	const unsigned int x = blockIdx.z * blockDim.z + threadIdx.z;

	double e = 0.0, h = 0.0;
	// same cells as Engine_Interface_FDTD::CalcFastEnergy: the last line in every direction is left out
	if (x + 1 < Nx && y + 1 < Ny && z + 1 < Nz)
	{
		const size_t k = ((size_t)x * Ny + y) * Nz + z;
		const float4 v = volt[k];
		const float4 i = curr[k];
		e = (double)(v.x * v.x) + (double)(v.y * v.y) + (double)(v.z * v.z);
		h = (double)(i.x * i.x) + (double)(i.y * i.y) + (double)(i.z * i.z);
	}

	for (int offset = 16; offset > 0; offset >>= 1)
	{
		e += __shfl_down_sync(0xffffffffu, e, offset);
		h += __shfl_down_sync(0xffffffffu, h, offset);
	}

	__shared__ double2 warpSum[8]; // block 32x4x2 = 8 warps
	const unsigned int tid = (threadIdx.z * blockDim.y + threadIdx.y) * blockDim.x + threadIdx.x;
	if ((tid & 31) == 0)
		warpSum[tid >> 5] = make_double2(e, h);
	__syncthreads();
	if (tid == 0)
	{
		double2 s = make_double2(0.0, 0.0);
		for (int w = 0; w < 8; ++w) { s.x += warpSum[w].x; s.y += warpSum[w].y; }
		partial[(blockIdx.z * gridDim.y + blockIdx.y) * gridDim.x + blockIdx.x] = s;
	}
}

float Engine_CUDA::ReadDeviceValue(const float4* d_ptr, size_t idx, unsigned int n) const
{
	// the copy waits for the kernels that were started before (default stream)
	float v = 0.0f;
	CUDA_CHECK(cudaMemcpy(&v, (const float*)d_ptr + idx * 4 + n, sizeof(float), cudaMemcpyDeviceToHost));
	return v;
}

void Engine_CUDA::CalcEnergySums(double& E, double& H)
{
	SyncToDevice(); // host side changes (not yet on the GPU) are part of the fields
	const size_t blocks = (size_t)m_gridDim.x * m_gridDim.y * m_gridDim.z;
	if (m_numPartial < blocks)
	{
		if (d_partial) cudaFree(d_partial);
		d_partial = NULL;
		CUDA_CHECK(cudaMalloc((void**)&d_partial, blocks * sizeof(double2)));
		m_numPartial = blocks;
	}
	EnergyKernel<<<m_gridDim, m_blockDim>>>(d_volt, d_curr, numLines[0], numLines[1], numLines[2], d_partial);
	CUDA_CHECK(cudaGetLastError());
	std::vector<double2> part(blocks);
	CUDA_CHECK(cudaMemcpy(part.data(), d_partial, blocks * sizeof(double2), cudaMemcpyDeviceToHost));
	E = 0.0; H = 0.0;
	for (size_t b = 0; b < blocks; ++b) { E += part[b].x; H += part[b].y; }
}

bool Engine_CUDA::IterateTS(unsigned int iterTS)
{
	// changes made on the host (SetVolt/SetCurr) must reach the GPU before computing
	SyncToDevice();

	for (unsigned int iter = 0; iter < iterTS; ++iter)
	{
		// same order as Engine::IterateTS
		//voltage updates with extensions
		DoPreVoltageUpdates();
		RunVoltageKernel();
		DoPostVoltageUpdates();
		Apply2Voltages();

		//current updates with extensions
		DoPreCurrentUpdates();
		RunCurrentKernel();
		DoPostCurrentUpdates();
		Apply2Current();

		++numTS;
	}
	// errors that happen while the kernels run (e.g. illegal memory access) show up here
	CUDA_CHECK(cudaDeviceSynchronize());
	return true;
}

//! Compare the CUDA kernels against a plain CPU implementation of the same update equations
//! on random fields. Enabled by the environment variable OPENEMS_CUDA_SELFTEST=<number of steps>.
//! Also checks the host<->GPU synchronisation. Needs several host copies of the grid, so use it
//! on a small model only.
void Engine_CUDA::SelfTest(unsigned int steps)
{
	const size_t Nx = numLines[0], Ny = numLines[1], Nz = numLines[2];
	const size_t N = m_numCells;
	auto idx = [&](size_t x, size_t y, size_t z) { return (x * Ny + y) * Nz + z; };

	cout << "CUDA self-test: " << steps << " time steps on " << Nx << "x" << Ny << "x" << Nz << " cells" << endl;

	std::vector<float4> hv(N), hc(N);
	srand(12345);
	auto rnd = []() { return 2.0f * (float)rand() / (float)RAND_MAX - 1.0f; };
	for (size_t x = 0; x < Nx; ++x)
		for (size_t y = 0; y < Ny; ++y)
			for (size_t z = 0; z < Nz; ++z)
			{
				const size_t k = idx(x, y, z);
				hv[k].x = rnd(); hv[k].y = rnd(); hv[k].z = rnd(); hv[k].w = 0.0f;
				hc[k].x = rnd(); hc[k].y = rnd(); hc[k].z = rnd(); hc[k].w = 0.0f;
				// fill the engine through the public accessors (tests the host mirror and the upload)
				for (unsigned int n = 0; n < 3; ++n)
				{
					SetVolt(n, (unsigned int)x, (unsigned int)y, (unsigned int)z, CUDA_F4Get(hv[k], n));
					SetCurr(n, (unsigned int)x, (unsigned int)y, (unsigned int)z, CUDA_F4Get(hc[k], n));
				}
			}

	const std::vector<float4>& hvv = Op->m_vv;
	const std::vector<float4>& hvi = Op->m_vi;
	const std::vector<float4>& hii = Op->m_ii;
	const std::vector<float4>& hiv = Op->m_iv;

	// CPU reference (same equations as Engine::UpdateVoltages / UpdateCurrents)
	for (unsigned int t = 0; t < steps; ++t)
	{
		for (size_t x = 0; x < Nx; ++x)
			for (size_t y = 0; y < Ny; ++y)
				for (size_t z = 0; z < Nz; ++z)
				{
					const size_t k = idx(x, y, z);
					const float4 i = hc[k], vv = hvv[k], vi = hvi[k];
					const float4 ix = hc[idx(x - (x != 0), y, z)];
					const float4 iy = hc[idx(x, y - (y != 0), z)];
					const float4 iz = hc[idx(x, y, z - (z != 0))];
					float4 v = hv[k];
					v.x = v.x * vv.x + vi.x * (i.z - iy.z - i.y + iz.y);
					v.y = v.y * vv.y + vi.y * (i.x - iz.x - i.z + ix.z);
					v.z = v.z * vv.z + vi.z * (i.y - ix.y - i.x + iy.x);
					hv[k] = v;
				}
		for (size_t x = 0; x + 1 < Nx; ++x)
			for (size_t y = 0; y + 1 < Ny; ++y)
				for (size_t z = 0; z + 1 < Nz; ++z)
				{
					const size_t k = idx(x, y, z);
					const float4 v = hv[k], ii = hii[k], iv = hiv[k];
					const float4 vx = hv[idx(x + 1, y, z)];
					const float4 vy = hv[idx(x, y + 1, z)];
					const float4 vz = hv[idx(x, y, z + 1)];
					float4 i = hc[k];
					i.x = i.x * ii.x + iv.x * (v.z - vy.z - v.y + vz.y);
					i.y = i.y * ii.y + iv.y * (v.x - vz.x - v.z + vx.z);
					i.z = i.z * ii.z + iv.z * (v.y - vx.y - v.x + vy.x);
					hc[k] = i;
				}
	}

	const unsigned int savedTS = numTS;
	IterateTS(steps);
	numTS = savedTS;

	// read the result through the public accessors (tests the download)
	double maxRef = 0.0, maxErr = 0.0;
	for (size_t x = 0; x < Nx; ++x)
		for (size_t y = 0; y < Ny; ++y)
			for (size_t z = 0; z < Nz; ++z)
			{
				const size_t k = idx(x, y, z);
				for (unsigned int n = 0; n < 3; ++n)
				{
					const float rv = CUDA_F4Get(hv[k], n);
					const float rc = CUDA_F4Get(hc[k], n);
					const float gv = GetVolt(n, (unsigned int)x, (unsigned int)y, (unsigned int)z);
					const float gc = GetCurr(n, (unsigned int)x, (unsigned int)y, (unsigned int)z);
					maxRef = std::max(maxRef, (double)std::fabs(rv));
					maxRef = std::max(maxRef, (double)std::fabs(rc));
					maxErr = std::max(maxErr, (double)std::fabs(rv - gv));
					maxErr = std::max(maxErr, (double)std::fabs(rc - gc));
				}
			}

	const double rel = (maxRef > 0.0) ? maxErr / maxRef : maxErr;
	cout << "CUDA self-test: max |ref| = " << maxRef << ", max abs error = " << maxErr << ", relative = " << rel << endl;

	// round trip: host write -> GPU -> host read
	const unsigned int cx = (unsigned int)(Nx / 2), cy = (unsigned int)(Ny / 2), cz = (unsigned int)(Nz / 2);
	SetVolt(1, cx, cy, cz, 3.5f);
	SyncToDevice();
	const float4 zero = {0.0f, 0.0f, 0.0f, 0.0f};
	std::fill(m_h_volt.begin(), m_h_volt.end(), zero);
	MarkHostStale();
	const bool roundTripOk = (GetVolt(1, cx, cy, cz) == 3.5f);
	cout << "CUDA self-test: host<->GPU round trip " << (roundTripOk ? "OK" : "FAILED") << endl;

	// restore zero fields for the real simulation
	std::fill(m_h_volt.begin(), m_h_volt.end(), zero);
	std::fill(m_h_curr.begin(), m_h_curr.end(), zero);
	CUDA_CHECK(cudaMemset(d_volt, 0, m_numCells * sizeof(float4)));
	CUDA_CHECK(cudaMemset(d_curr, 0, m_numCells * sizeof(float4)));
	m_host_stale = false;
	m_device_stale = false;

	if (!(rel < 1e-4))
		throw std::runtime_error("CUDA self-test FAILED: CUDA kernels differ from the CPU reference");
	if (!roundTripOk)
		throw std::runtime_error("CUDA self-test FAILED: host<->GPU synchronisation is broken");
	cout << "CUDA self-test: OK" << endl;
}
