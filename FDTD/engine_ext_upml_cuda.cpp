#include "engine_ext_upml_cuda.h"
#include "engine_cuda.h"
#include "extensions/operator_ext_upml.h"

#include <stdexcept>
#include <string>
#include <vector>

#define UPML_CUDA_CHECK(call) \
	do { \
		cudaError_t err_ = (call); \
		if (err_ != cudaSuccess) \
			throw std::runtime_error(std::string("CUDA UPML: ") + cudaGetErrorString(err_) \
				+ " (" + __FILE__ + ":" + std::to_string(__LINE__) + ")"); \
	} while (0)

//! pack the three components arr[0..2][x][y][z] of a PML box into one compact float4 array on the GPU
static float4* UploadBoxArray(FDTD_FLOAT**** arr, const unsigned int n[3])
{
	const size_t cells = (size_t)n[0] * n[1] * n[2];
	std::vector<float4> h(cells);
	for (unsigned int x = 0; x < n[0]; ++x)
		for (unsigned int y = 0; y < n[1]; ++y)
			for (unsigned int z = 0; z < n[2]; ++z)
			{
				float4& v = h[((size_t)x * n[1] + y) * n[2] + z];
				v.x = (float)arr[0][x][y][z];
				v.y = (float)arr[1][x][y][z];
				v.z = (float)arr[2][x][y][z];
				v.w = 0.0f;
			}
	float4* d = NULL;
	UPML_CUDA_CHECK(cudaMalloc((void**)&d, cells * sizeof(float4)));
	UPML_CUDA_CHECK(cudaMemcpy(d, h.data(), cells * sizeof(float4), cudaMemcpyHostToDevice));
	return d;
}

Engine_Ext_UPML_CUDA::Engine_Ext_UPML_CUDA(Operator_Ext_UPML* op_ext, Engine_CUDA* eng) : Engine_Extension(op_ext)
{
	m_EngCuda = eng;
	d_vv = d_vvfo = d_vvfn = d_ii = d_iifo = d_iifn = NULL;
	d_volt_flux = d_curr_flux = NULL;

	// same priority as the host version: must run first
	m_Priority = ENG_EXT_PRIO_UPML;

	for (int n = 0; n < 3; ++n)
	{
		m_Geom.start[n] = op_ext->m_StartPos[n];
		m_Geom.n[n]     = op_ext->m_numLines[n];
		m_Geom.N[n]     = eng->GetNumLines(n);
		if (m_Geom.start[n] + m_Geom.n[n] > m_Geom.N[n])
			throw std::runtime_error("CUDA UPML: PML box lies outside of the FDTD grid");
	}
	m_BoxCells = (size_t)m_Geom.n[0] * m_Geom.n[1] * m_Geom.n[2];

	try
	{
		d_vv   = UploadBoxArray(op_ext->vv,   m_Geom.n);
		d_vvfo = UploadBoxArray(op_ext->vvfo, m_Geom.n);
		d_vvfn = UploadBoxArray(op_ext->vvfn, m_Geom.n);
		d_ii   = UploadBoxArray(op_ext->ii,   m_Geom.n);
		d_iifo = UploadBoxArray(op_ext->iifo, m_Geom.n);
		d_iifn = UploadBoxArray(op_ext->iifn, m_Geom.n);

		const size_t bytes = m_BoxCells * sizeof(float4);
		UPML_CUDA_CHECK(cudaMalloc((void**)&d_volt_flux, bytes));
		UPML_CUDA_CHECK(cudaMalloc((void**)&d_curr_flux, bytes));
		UPML_CUDA_CHECK(cudaMemset(d_volt_flux, 0, bytes));
		UPML_CUDA_CHECK(cudaMemset(d_curr_flux, 0, bytes));
	}
	catch (...)
	{
		Free();
		throw;
	}
}

Engine_Ext_UPML_CUDA::~Engine_Ext_UPML_CUDA()
{
	Free();
}

void Engine_Ext_UPML_CUDA::Free()
{
	float4** ptrs[] = {&d_vv, &d_vvfo, &d_vvfn, &d_ii, &d_iifo, &d_iifn, &d_volt_flux, &d_curr_flux};
	for (size_t n = 0; n < sizeof(ptrs) / sizeof(ptrs[0]); ++n)
	{
		if (*ptrs[n])
			cudaFree(*ptrs[n]);
		*ptrs[n] = NULL;
	}
}

std::string Engine_Ext_UPML_CUDA::GetExtensionName() const
{
	return Engine_Extension::GetExtensionName() + " (GPU)";
}

void Engine_Ext_UPML_CUDA::DoPreVoltageUpdates()
{
	m_EngCuda->DeviceBegin();
	UPML_CUDA_CHECK(UPML_LaunchPre(m_EngCuda->d_volt, d_volt_flux, d_vv, d_vvfo, m_Geom));
	m_EngCuda->DeviceEnd();
}

void Engine_Ext_UPML_CUDA::DoPostVoltageUpdates()
{
	m_EngCuda->DeviceBegin();
	UPML_CUDA_CHECK(UPML_LaunchPost(m_EngCuda->d_volt, d_volt_flux, d_vvfn, m_Geom));
	m_EngCuda->DeviceEnd();
}

void Engine_Ext_UPML_CUDA::DoPreCurrentUpdates()
{
	m_EngCuda->DeviceBegin();
	UPML_CUDA_CHECK(UPML_LaunchPre(m_EngCuda->d_curr, d_curr_flux, d_ii, d_iifo, m_Geom));
	m_EngCuda->DeviceEnd();
}

void Engine_Ext_UPML_CUDA::DoPostCurrentUpdates()
{
	m_EngCuda->DeviceBegin();
	UPML_CUDA_CHECK(UPML_LaunchPost(m_EngCuda->d_curr, d_curr_flux, d_iifn, m_Geom));
	m_EngCuda->DeviceEnd();
}
