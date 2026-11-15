#include "excitation_kernels_cuda.h"

__global__ void ExcKernel(float* __restrict__ field, const unsigned long long* __restrict__ off,
                          const unsigned int* __restrict__ first, const float* __restrict__ amp,
                          const unsigned int* __restrict__ delay, unsigned int groups,
                          const float* __restrict__ signal, int numTS, int period, int length)
{
	const unsigned int g = blockIdx.x * blockDim.x + threadIdx.x;
	if (g >= groups) return;

	const unsigned long long o = off[g];
	float v = field[o];
	for (unsigned int k = first[g]; k < first[g + 1]; ++k)
	{
		int pos = numTS - (int)delay[k];
		pos *= (pos > 0);
		pos %= period;
		pos *= (pos < length);

		// explicit rounding of the product and of the sum: no fused multiply-add, same result as the host
		v = __fadd_rn(v, __fmul_rn(amp[k], signal[pos]));
	}
	field[o] = v;
}

cudaError_t Exc_Launch(float* field, const unsigned long long* off, const unsigned int* first,
                       const float* amp, const unsigned int* delay, unsigned int groups,
                       const float* signal, int numTS, int period, int length)
{
	if (groups == 0) return cudaSuccess;
	const unsigned int block = 128;
	const unsigned int grid = (groups + block - 1) / block;
	ExcKernel<<<grid, block>>>(field, off, first, amp, delay, groups, signal, numTS, period, length);
	return cudaGetLastError();
}
