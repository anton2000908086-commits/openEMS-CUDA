#ifndef ENGINE_EXT_EXCITATION_CUDA_H
#define ENGINE_EXT_EXCITATION_CUDA_H

#include <string>
#include "extensions/engine_extension.h"
#include "excitation_kernels_cuda.h"

class Operator_Ext_Excitation;
class Engine_CUDA;

//! Soft voltage/current excitation on the GPU. Signal, cell offsets, amplitudes and delays are
//! uploaded once; per time step only the step number is passed to the kernel.
class Engine_Ext_Excitation_CUDA : public Engine_Extension
{
public:
	Engine_Ext_Excitation_CUDA(Operator_Ext_Excitation* op_ext, Engine_CUDA* eng);
	virtual ~Engine_Ext_Excitation_CUDA();

	virtual void Apply2Voltages();
	virtual void Apply2Current();

	virtual std::string GetExtensionName() const;

private:
	Engine_CUDA* m_EngCuda;
	Operator_Ext_Excitation* m_Op_Exc;

	int m_Length;
	int m_PeriodSteps; //!< signal period in time steps, 0: no periodic signal

	unsigned int m_VoltCount, m_CurrCount;
	float* d_sigVolt; float* d_sigCurr;
	unsigned long long* d_voltOff; float* d_voltAmp; unsigned int* d_voltDelay;
	unsigned long long* d_currOff; float* d_currAmp; unsigned int* d_currDelay;

	void Free();
	void Apply(float* field, unsigned long long* off, float* amp, unsigned int* delay, unsigned int count, float* sig);
};

#endif // ENGINE_EXT_EXCITATION_CUDA_H
