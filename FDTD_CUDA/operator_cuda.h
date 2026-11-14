#ifndef OPERATOR_CUDA_H
#define OPERATOR_CUDA_H

#include <vector>

#include "cuda_vec.h"
#include "engine_cuda.h"
#include "operator.h"

//! CUDA FDTD-operator
/*!
  The operator coefficients are built on the host, in flat arrays with the index (x*Ny+y)*Nz+z.
  Engine_CUDA copies them to the GPU once, when the engine is created.
*/
class Operator_CUDA : public Operator
{
	friend class Engine_CUDA;

public:
	static Operator_CUDA* New(unsigned int cuda_device_number = 0);

	virtual void setCUDAdevice(unsigned int cuda_device_number);

	void InitOperator();
	void Delete();

	virtual Engine* CreateEngine();

	// the base class also has overloads taking a position array
	using Operator::GetVV;
	using Operator::GetVI;
	using Operator::GetII;
	using Operator::GetIV;

	inline virtual FDTD_FLOAT GetVV( unsigned int n, unsigned int x, unsigned int y, unsigned int z ) const { return CUDA_F4Get(m_vv[Index(x,y,z)], n); }
	inline virtual FDTD_FLOAT GetVI( unsigned int n, unsigned int x, unsigned int y, unsigned int z ) const { return CUDA_F4Get(m_vi[Index(x,y,z)], n); }
	inline virtual FDTD_FLOAT GetII( unsigned int n, unsigned int x, unsigned int y, unsigned int z ) const { return CUDA_F4Get(m_ii[Index(x,y,z)], n); }
	inline virtual FDTD_FLOAT GetIV( unsigned int n, unsigned int x, unsigned int y, unsigned int z ) const { return CUDA_F4Get(m_iv[Index(x,y,z)], n); }

	inline virtual void SetVV( unsigned int n, unsigned int x, unsigned int y, unsigned int z, FDTD_FLOAT value ) { CUDA_F4Set(m_vv[Index(x,y,z)], n, value); }
	inline virtual void SetVI( unsigned int n, unsigned int x, unsigned int y, unsigned int z, FDTD_FLOAT value ) { CUDA_F4Set(m_vi[Index(x,y,z)], n, value); }
	inline virtual void SetII( unsigned int n, unsigned int x, unsigned int y, unsigned int z, FDTD_FLOAT value ) { CUDA_F4Set(m_ii[Index(x,y,z)], n, value); }
	inline virtual void SetIV( unsigned int n, unsigned int x, unsigned int y, unsigned int z, FDTD_FLOAT value ) { CUDA_F4Set(m_iv[Index(x,y,z)], n, value); }

protected:
	//! linear index of a cell in the flat arrays
	inline size_t Index( unsigned int x, unsigned int y, unsigned int z ) const
	{
		return ((size_t)x * numLines[1] + y) * numLines[2] + z;
	}

	//EC operator, host copy, flat arrays of float4 (the 4th component is unused)
	std::vector<float4> m_vv; //calc new voltage from old voltage
	std::vector<float4> m_vi; //calc new voltage from old current
	std::vector<float4> m_ii; //calc new current from old current
	std::vector<float4> m_iv; //calc new current from old voltage

	unsigned int m_cuda_device_number;
};

#endif // OPERATOR_CUDA_H
