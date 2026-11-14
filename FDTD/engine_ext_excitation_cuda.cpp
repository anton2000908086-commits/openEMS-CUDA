#include "engine_ext_excitation_cuda.h"
#include "engine_cuda.h"
#include "excitation.h"
#include "extensions/operator_ext_excitation.h"

#include <stdexcept>
#include <string>
#include <vector>

#define EXC_CUDA_CHECK(call) \
	do { \
		cudaError_t err_ = (call); \
		if (err_ != cudaSuccess) \
			throw std::runtime_error(std::string("CUDA excitation: ") + cudaGetErrorString(err_) \
				+ " (" + __FILE__ + ":" + std::to_string(__LINE__) + ")"); \
	} while (0)

template <typename T>
static T* UploadVector(const std::vector<T>& h)
{
	if (h.empty()) return NULL;
	T* d = NULL;
	EXC_CUDA_CHECK(cudaMalloc((void**)&d, h.size() * sizeof(T)));
	EXC_CUDA_CHECK(cudaMemcpy(d, h.data(), h.size() * sizeof(T), cudaMemcpyHostToDevice));
	return d;
}

Engine_Ext_Excitation_CUDA::Engine_Ext_Excitation_CUDA(Operator_Ext_Excitation* op_ext, Engine_CUDA* eng) : Engine_Extension(op_ext)
{
	m_EngCuda = eng;
	m_Op_Exc = op_ext;
	m_Priority = ENG_EXT_PRIO_EXCITATION;

	d_sigVolt = d_sigCurr = NULL;
	d_voltOff = d_currOff = NULL;
	d_voltAmp = d_currAmp = NULL;
	d_voltDelay = d_currDelay = NULL;

	m_Length = (int)op_ext->m_Exc->GetLength();
	m_PeriodSteps = 0;
	if (op_ext->m_Exc->GetSignalPeriod() > 0)
		m_PeriodSteps = int(op_ext->m_Exc->GetSignalPeriod() / op_ext->m_Exc->GetTimestep());

	m_VoltCount = op_ext->Volt_Count;
	m_CurrCount = op_ext->Curr_Count;

	const unsigned int Ny = eng->GetNumLines(1), Nz = eng->GetNumLines(2);

	try
	{
		std::vector<float> sig;
		sig.assign(op_ext->m_Exc->GetVoltageSignal(), op_ext->m_Exc->GetVoltageSignal() + m_Length);
		d_sigVolt = UploadVector(sig);
		sig.assign(op_ext->m_Exc->GetCurrentSignal(), op_ext->m_Exc->GetCurrentSignal() + m_Length);
		d_sigCurr = UploadVector(sig);

		std::vector<unsigned long long> off;
		std::vector<float> amp;
		std::vector<unsigned int> delay;

		off.resize(m_VoltCount); amp.resize(m_VoltCount); delay.resize(m_VoltCount);
		for (unsigned int n = 0; n < m_VoltCount; ++n)
		{
			const unsigned long long cell = ((unsigned long long)op_ext->Volt_index[0][n] * Ny + op_ext->Volt_index[1][n]) * Nz + op_ext->Volt_index[2][n];
			off[n] = cell * 4 + op_ext->Volt_dir[n];
			amp[n] = (float)op_ext->Volt_amp[n];
			delay[n] = op_ext->Volt_delay[n];
		}
		d_voltOff = UploadVector(off); d_voltAmp = UploadVector(amp); d_voltDelay = UploadVector(delay);

		off.resize(m_CurrCount); amp.resize(m_CurrCount); delay.resize(m_CurrCount);
		for (unsigned int n = 0; n < m_CurrCount; ++n)
		{
			const unsigned long long cell = ((unsigned long long)op_ext->Curr_index[0][n] * Ny + op_ext->Curr_index[1][n]) * Nz + op_ext->Curr_index[2][n];
			off[n] = cell * 4 + op_ext->Curr_dir[n];
			amp[n] = (float)op_ext->Curr_amp[n];
			delay[n] = op_ext->Curr_delay[n];
		}
		d_currOff = UploadVector(off); d_currAmp = UploadVector(amp); d_currDelay = UploadVector(delay);
	}
	catch (...)
	{
		Free();
		throw;
	}
}

Engine_Ext_Excitation_CUDA::~Engine_Ext_Excitation_CUDA()
{
	Free();
}

void Engine_Ext_Excitation_CUDA::Free()
{
	void* ptrs[] = {d_sigVolt, d_sigCurr, d_voltOff, d_voltAmp, d_voltDelay, d_currOff, d_currAmp, d_currDelay};
	for (size_t n = 0; n < sizeof(ptrs) / sizeof(ptrs[0]); ++n)
		if (ptrs[n]) cudaFree(ptrs[n]);
	d_sigVolt = d_sigCurr = NULL;
	d_voltOff = d_currOff = NULL;
	d_voltAmp = d_currAmp = NULL;
	d_voltDelay = d_currDelay = NULL;
}

std::string Engine_Ext_Excitation_CUDA::GetExtensionName() const
{
	return Engine_Extension::GetExtensionName() + " (GPU)";
}

void Engine_Ext_Excitation_CUDA::Apply(float* field, unsigned long long* off, float* amp, unsigned int* delay, unsigned int count, float* sig)
{
	if (count == 0)
		return;
	const int numTS = (int)m_EngCuda->GetNumberOfTimesteps();
	// same as the host version: without a signal period the period is longer than any time step
	int p = (m_PeriodSteps > 0) ? m_PeriodSteps : numTS + 1;
	if (p <= 0) p = 1;
	m_EngCuda->DeviceBegin();
	EXC_CUDA_CHECK(Exc_Launch(field, off, amp, delay, count, sig, numTS, p, m_Length));
	m_EngCuda->DeviceEnd();
}

void Engine_Ext_Excitation_CUDA::Apply2Voltages()
{
	Apply((float*)m_EngCuda->d_volt, d_voltOff, d_voltAmp, d_voltDelay, m_VoltCount, d_sigVolt);
}

void Engine_Ext_Excitation_CUDA::Apply2Current()
{
	Apply((float*)m_EngCuda->d_curr, d_currOff, d_currAmp, d_currDelay, m_CurrCount, d_sigCurr);
}
