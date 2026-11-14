#include "excitation_kernels_cuda.h"

__global__ void ExcKernel(float* __restrict__ field, const unsigned long long* __restrict__ off,
                          const float* __restrict__ amp, const unsigned int* __restrict__ delay,
                          unsigned int count, const float* __restrict__ signal,
                          int numTS, int period, int length)
{
	const unsigned int n = blockIdx.x * blockDim.x + threadIdx.x;
	if (n >= count) return;

	int pos = numTS - (int)delay[n];
	pos *= (pos > 0);
	pos %= period;
	pos *= (pos < length);

	atomicAdd(&field[off[n]], amp[n] * signal[pos]);
}

cudaError_t Exc_Launch(float* field, const unsigned long long* off, const float* amp, const unsigned int* delay,
                       unsigned int count, const float* signal, int numTS, int period, int length)
{
	if (count == 0) return cudaSuccess;
	const unsigned int block = 128;
	const unsigned int grid = (count + block - 1) / block;
	ExcKernel<<<grid, block>>>(field, off, amp, delay, count, signal, numTS, period, length);
	return cudaGetLastError();
}
