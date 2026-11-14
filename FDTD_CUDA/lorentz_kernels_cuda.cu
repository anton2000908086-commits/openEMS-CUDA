#include "lorentz_kernels_cuda.h"

__global__ void LorPreKernel(const float4* __restrict__ field, const unsigned long long* __restrict__ cell,
                             unsigned int count, float4* __restrict__ ade, float4* __restrict__ lor,
                             const float4* __restrict__ cLor, const float4* __restrict__ cInt,
                             const float4* __restrict__ cExt)
{
	const unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
	if (i >= count) return;

	const float4 f = field[cell[i]];
	float4 a = ade[i];
	const float4 ci = cInt[i];
	const float4 ce = cExt[i];

	if (lor != 0)
	{
		float4 l = lor[i];
		const float4 cl = cLor[i];
		l.x += cl.x * a.x;  a.x *= ci.x;  a.x += ce.x * (f.x - l.x);
		l.y += cl.y * a.y;  a.y *= ci.y;  a.y += ce.y * (f.y - l.y);
		l.z += cl.z * a.z;  a.z *= ci.z;  a.z += ce.z * (f.z - l.z);
		lor[i] = l;
	}
	else
	{
		a.x *= ci.x;  a.x += ce.x * f.x;
		a.y *= ci.y;  a.y += ce.y * f.y;
		a.z *= ci.z;  a.z += ce.z * f.z;
	}
	ade[i] = a;
}

__global__ void LorApplyKernel(float4* __restrict__ field, const unsigned long long* __restrict__ cell,
                               unsigned int count, const float4* __restrict__ ade)
{
	const unsigned int i = blockIdx.x * blockDim.x + threadIdx.x;
	if (i >= count) return;

	float4 f = field[cell[i]];
	const float4 a = ade[i];
	f.x -= a.x;
	f.y -= a.y;
	f.z -= a.z;
	field[cell[i]] = f;
}

cudaError_t Lor_LaunchPre(const float4* field, const unsigned long long* cell, unsigned int count,
                          float4* ade, float4* lor, const float4* cLor, const float4* cInt, const float4* cExt)
{
	if (count == 0) return cudaSuccess;
	const unsigned int block = 128;
	LorPreKernel<<<(count + block - 1) / block, block>>>(field, cell, count, ade, lor, cLor, cInt, cExt);
	return cudaGetLastError();
}

cudaError_t Lor_LaunchApply(float4* field, const unsigned long long* cell, unsigned int count, const float4* ade)
{
	if (count == 0) return cudaSuccess;
	const unsigned int block = 128;
	LorApplyKernel<<<(count + block - 1) / block, block>>>(field, cell, count, ade);
	return cudaGetLastError();
}
