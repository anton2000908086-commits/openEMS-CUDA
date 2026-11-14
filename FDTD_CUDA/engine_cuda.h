#ifndef ENGINE_CUDA_H
#define ENGINE_CUDA_H

#include <cuda_runtime.h>
#include <vector>

#include "cuda_vec.h"
#include "engine.h"
#include "operator_cuda.h"

class Operator_CUDA;

//! CUDA FDTD engine
/*!
  The fields and the operator coefficients live in flat float4 arrays in GPU memory
  (index (x*Ny+y)*Nz+z). The host keeps a mirror of the fields for the element-wise
  Get/Set functions used by the processing code. The mirror is synchronised lazily:
  - after IterateTS() the GPU has newer data; the first Get/Set call copies the fields to the host once
  - after a SetVolt()/SetCurr() the host has newer data; the next IterateTS() uploads it
  Both copies can also be triggered explicitly with SyncToHost() and SyncToDevice().
*/
class Engine_CUDA : public Engine
{
public:
	static Engine_CUDA* New(const Operator_CUDA* op, unsigned int cuda_device_number);

	virtual void Init();
	virtual void Reset();

	//! Compare the kernels with a CPU reference on random fields (OPENEMS_CUDA_SELFTEST=<steps>)
	void SelfTest(unsigned int steps);

	virtual void setCUDAdevice(unsigned int cuda_device_number);

	//!Iterate a number of timesteps
	virtual bool IterateTS(unsigned int iterTS);

	//! Copy the fields from the GPU to the host mirror (does nothing if the mirror is current)
	void SyncToHost() const;
	//! Copy the host mirror of the fields to the GPU (does nothing if the GPU is current)
	void SyncToDevice();

	//! For GPU extensions: call before a kernel that works on d_volt/d_curr (uploads pending host changes)
	void DeviceBegin() { SyncToDevice(); }
	//! For GPU extensions: call after such a kernel (the host mirror is outdated now)
	void DeviceEnd() const { MarkHostStale(); }
	unsigned int GetNumLines(unsigned int n) const { return numLines[n]; }

	//! Sums of the squared voltages (E) and currents (H) over all cells that have an upper neighbour, computed on the GPU
	void CalcEnergySums(double& E, double& H);

	inline virtual FDTD_FLOAT GetVolt( unsigned int n, unsigned int x, unsigned int y, unsigned int z )		const { return ReadField(d_volt, m_h_volt, n, Index(x,y,z)); }
	inline virtual FDTD_FLOAT GetVolt( unsigned int n, const unsigned int pos[3] )							const { return ReadField(d_volt, m_h_volt, n, Index(pos[0],pos[1],pos[2])); }
	inline virtual FDTD_FLOAT GetCurr( unsigned int n, unsigned int x, unsigned int y, unsigned int z )		const { return ReadField(d_curr, m_h_curr, n, Index(x,y,z)); }
	inline virtual FDTD_FLOAT GetCurr( unsigned int n, const unsigned int pos[3] )							const { return ReadField(d_curr, m_h_curr, n, Index(pos[0],pos[1],pos[2])); }

	inline virtual void SetVolt( unsigned int n, unsigned int x, unsigned int y, unsigned int z, FDTD_FLOAT value)	{ CUDA_F4Set(HostVoltWrite(x,y,z), n, value); }
	inline virtual void SetVolt( unsigned int n, const unsigned int pos[3], FDTD_FLOAT value )						{ CUDA_F4Set(HostVoltWrite(pos[0],pos[1],pos[2]), n, value); }
	inline virtual void SetCurr( unsigned int n, unsigned int x, unsigned int y, unsigned int z, FDTD_FLOAT value)	{ CUDA_F4Set(HostCurrWrite(x,y,z), n, value); }
	inline virtual void SetCurr( unsigned int n, const unsigned int pos[3], FDTD_FLOAT value )						{ CUDA_F4Set(HostCurrWrite(pos[0],pos[1],pos[2]), n, value); }

	Engine_CUDA(const Operator_CUDA* op);
	virtual ~Engine_CUDA();
	const Operator_CUDA* Op;

	unsigned int m_cuda_device_number;
	int m_supports_coop_launch;
	dim3 m_gridDim;
	dim3 m_blockDim;

	size_t m_numCells;

	//! GPU arrays, flat, index (x*Ny+y)*Nz+z
	float4* d_volt;
	float4* d_curr;
	float4* d_vv; //calc new voltage from old voltage
	float4* d_vi; //calc new voltage from old current
	float4* d_ii; //calc new current from old current
	float4* d_iv; //calc new current from old voltage

protected:
	//! GPU version of an extension if there is one, host version otherwise (engine_cuda_ext.cpp)
	virtual void InitExtensions();

	inline size_t Index( unsigned int x, unsigned int y, unsigned int z ) const
	{
		return ((size_t)x * numLines[1] + y) * numLines[2] + z;
	}

	inline const float4& HostVolt( unsigned int x, unsigned int y, unsigned int z ) const
	{
		if (m_host_stale) SyncToHost();
		return m_h_volt[Index(x,y,z)];
	}
	inline const float4& HostCurr( unsigned int x, unsigned int y, unsigned int z ) const
	{
		if (m_host_stale) SyncToHost();
		return m_h_curr[Index(x,y,z)];
	}
	//! access for writing: pulls newer GPU data first, so that a partial write does not lose it
	inline float4& HostVoltWrite( unsigned int x, unsigned int y, unsigned int z )
	{
		if (m_host_stale) SyncToHost();
		m_device_stale = true;
		return m_h_volt[Index(x,y,z)];
	}
	inline float4& HostCurrWrite( unsigned int x, unsigned int y, unsigned int z )
	{
		if (m_host_stale) SyncToHost();
		m_device_stale = true;
		return m_h_curr[Index(x,y,z)];
	}

	//! Read one field value. While the GPU holds newer data than the host mirror a few single values are
	//! read straight from the GPU (a probe needs only a handful of cells); once more are read than a full
	//! download would cost, the whole mirror is copied once instead.
	inline float ReadField( const float4* d_ptr, const std::vector<float4>& mirror, unsigned int n, size_t idx ) const
	{
		if (m_host_stale)
		{
			if (m_pointReads < m_pointReadLimit)
			{
				++m_pointReads;
				return ReadDeviceValue(d_ptr, idx, n);
			}
			SyncToHost();
		}
		return CUDA_F4Get(mirror[idx], n);
	}
	float ReadDeviceValue( const float4* d_ptr, size_t idx, unsigned int n ) const;
	inline void MarkHostStale() const { m_host_stale = true; m_pointReads = 0; }

	double2* d_partial; //!< per-block partial sums of CalcEnergySums
	size_t m_numPartial;

	void FreeDevice();	void RunVoltageKernel();
	void RunCurrentKernel();

	mutable std::vector<float4> m_h_volt; //!< host mirror of the voltages
	mutable std::vector<float4> m_h_curr; //!< host mirror of the currents
	mutable unsigned int m_pointReads;     //!< single values read from the GPU since the host mirror became outdated
	unsigned int m_pointReadLimit;         //!< more single reads than this: copy the whole mirror instead
	mutable bool m_host_stale;   //!< the GPU holds newer fields than the host mirror
	bool m_device_stale;         //!< the host mirror holds changes that are not on the GPU yet
};

#endif // ENGINE_CUDA_H
