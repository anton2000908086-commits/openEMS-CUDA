#ifndef CUDA_VEC_H
#define CUDA_VEC_H

#include <cuda_runtime.h>

//! read component n (0..2) of a float4 field vector
inline float CUDA_F4Get(const float4& v, unsigned int n)
{
	return (n == 0) ? v.x : ((n == 1) ? v.y : v.z);
}

//! write component n (0..2) of a float4 field vector
inline void CUDA_F4Set(float4& v, unsigned int n, float value)
{
	if (n == 0) v.x = value;
	else if (n == 1) v.y = value;
	else v.z = value;
}

#endif // CUDA_VEC_H
