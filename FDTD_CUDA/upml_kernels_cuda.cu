#include "upml_kernels_cuda.h"

// threadIdx.x -> z (fastest index in memory), threadIdx.y -> y, threadIdx.z -> x
// The box arrays (coefficients, flux) are stored compactly, index (lx*ny+ly)*nz+lz.
// The field arrays are the full FDTD grid, index (x*Ny+y)*Nz+z.

__global__ void UPMLPreKernel(float4* __restrict__ field, float4* __restrict__ flux,
                              const float4* __restrict__ c, const float4* __restrict__ cfo,
                              UPMLBoxGeom g)
{
	const unsigned int lz = blockIdx.x * blockDim.x + threadIdx.x;
	const unsigned int ly = blockIdx.y * blockDim.y + threadIdx.y;
	const unsigned int lx = blockIdx.z * blockDim.z + threadIdx.z;
	if (lx >= g.n[0] || ly >= g.n[1] || lz >= g.n[2]) return;

	const size_t kl = ((size_t)lx * g.n[1] + ly) * g.n[2] + lz;
	const size_t kg = ((size_t)(g.start[0] + lx) * g.N[1] + (g.start[1] + ly)) * g.N[2] + (g.start[2] + lz);

	float4 f  = field[kg];
	float4 fl = flux[kl];
	const float4 cc = c[kl];
	const float4 co = cfo[kl];

	float4 nfl = fl;
	nfl.x = cc.x * f.x - co.x * fl.x;
	nfl.y = cc.y * f.y - co.y * fl.y;
	nfl.z = cc.z * f.z - co.z * fl.z;

	f.x = fl.x; f.y = fl.y; f.z = fl.z;

	field[kg] = f;
	flux[kl]  = nfl;
}

__global__ void UPMLPostKernel(float4* __restrict__ field, float4* __restrict__ flux,
                               const float4* __restrict__ cfn, UPMLBoxGeom g)
{
	const unsigned int lz = blockIdx.x * blockDim.x + threadIdx.x;
	const unsigned int ly = blockIdx.y * blockDim.y + threadIdx.y;
	const unsigned int lx = blockIdx.z * blockDim.z + threadIdx.z;
	if (lx >= g.n[0] || ly >= g.n[1] || lz >= g.n[2]) return;

	const size_t kl = ((size_t)lx * g.n[1] + ly) * g.n[2] + lz;
	const size_t kg = ((size_t)(g.start[0] + lx) * g.N[1] + (g.start[1] + ly)) * g.N[2] + (g.start[2] + lz);

	float4 f  = field[kg];
	const float4 fl = flux[kl];
	const float4 cn = cfn[kl];

	float4 nfl = fl;
	nfl.x = f.x; nfl.y = f.y; nfl.z = f.z;

	f.x = fl.x + cn.x * nfl.x;
	f.y = fl.y + cn.y * nfl.y;
	f.z = fl.z + cn.z * nfl.z;

	field[kg] = f;
	flux[kl]  = nfl;
}

static void LaunchConfig(const UPMLBoxGeom& g, dim3& grid, dim3& block)
{
	block = dim3(32, 4, 2);
	grid = dim3((g.n[2] + block.x - 1) / block.x,
	            (g.n[1] + block.y - 1) / block.y,
	            (g.n[0] + block.z - 1) / block.z);
}

cudaError_t UPML_LaunchPre(float4* field, float4* flux, const float4* c, const float4* cfo, const UPMLBoxGeom& g)
{
	dim3 grid, block;
	LaunchConfig(g, grid, block);
	if (grid.y > 65535 || grid.z > 65535) return cudaErrorInvalidConfiguration;
	UPMLPreKernel<<<grid, block>>>(field, flux, c, cfo, g);
	return cudaGetLastError();
}

cudaError_t UPML_LaunchPost(float4* field, float4* flux, const float4* cfn, const UPMLBoxGeom& g)
{
	dim3 grid, block;
	LaunchConfig(g, grid, block);
	if (grid.y > 65535 || grid.z > 65535) return cudaErrorInvalidConfiguration;
	UPMLPostKernel<<<grid, block>>>(field, flux, cfn, g);
	return cudaGetLastError();
}
