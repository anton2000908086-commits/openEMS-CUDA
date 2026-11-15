#include "engine_ext_excitation_cuda.h"
#include "engine_cuda.h"
#include "excitation.h"
#include "extensions/operator_ext_excitation.h"

#include <algorithm>
#include <iostream>
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

	m_Length = (int)op_ext->m_Exc->GetLength();
	m_PeriodSteps = 0;
	if (op_ext->m_Exc->GetSignalPeriod() > 0)
		m_PeriodSteps = int(op_ext->m_Exc->GetSignalPeriod() / op_ext->m_Exc->GetTimestep());

	try
	{
		Build(m_Volt, op_ext->m_Exc->GetVoltageSignal(), op_ext->Volt_Count, op_ext->Volt_index,
		      op_ext->Volt_dir, op_ext->Volt_amp, op_ext->Volt_delay, "voltage");
		Build(m_Curr, op_ext->m_Exc->GetCurrentSignal(), op_ext->Curr_Count, op_ext->Curr_index,
		      op_ext->Curr_dir, op_ext->Curr_amp, op_ext->Curr_delay, "current");
	}
	catch (...)
	{
		Free(m_Volt);
		Free(m_Curr);
		throw;
	}
}

Engine_Ext_Excitation_CUDA::~Engine_Ext_Excitation_CUDA()
{
	Free(m_Volt);
	Free(m_Curr);
}

void Engine_Ext_Excitation_CUDA::Build(List& l, const float* signal, unsigned int count, unsigned int* const index[3],
                                       const unsigned short* dir, const float* amp, const unsigned int* delay, const char* name)
{
	const unsigned int Ny = m_EngCuda->GetNumLines(1), Nz = m_EngCuda->GetNumLines(2);

	std::vector<float> sig(signal, signal + m_Length);
	l.d_sig = UploadVector(sig);
	l.entries = count;
	if (count == 0)
		return;

	// field value addressed by every entry: 4*cell + component (the float4 array viewed as float)
	std::vector<unsigned long long> off(count);
	for (unsigned int n = 0; n < count; ++n)
	{
		const unsigned long long cell = ((unsigned long long)index[0][n] * Ny + index[1][n]) * Nz + index[2][n];
		off[n] = cell * 4 + dir[n];
	}

	// entries that address the same value form one group; inside a group the original order is kept
	std::vector<unsigned int> order(count);
	for (unsigned int n = 0; n < count; ++n)
		order[n] = n;
	std::stable_sort(order.begin(), order.end(), [&off](unsigned int a, unsigned int b) { return off[a] < off[b]; });

	std::vector<unsigned long long> gOff;
	std::vector<unsigned int> first;
	std::vector<float> gAmp(count);
	std::vector<unsigned int> gDelay(count);
	for (unsigned int k = 0; k < count; ++k)
	{
		const unsigned int n = order[k];
		if (k == 0 || off[n] != gOff.back())
		{
			gOff.push_back(off[n]);
			first.push_back(k);
		}
		gAmp[k] = amp[n];
		gDelay[k] = delay[n];
	}
	first.push_back(count);
	l.groups = (unsigned int)gOff.size();

	l.d_off = UploadVector(gOff);
	l.d_first = UploadVector(first);
	l.d_amp = UploadVector(gAmp);
	l.d_delay = UploadVector(gDelay);

	if (l.groups < count)
		std::cout << "  Excitation (" << name << "): " << count - l.groups << " of " << count
		          << " entries address a field value that another entry addresses too; they are summed in a fixed order" << std::endl;
}

void Engine_Ext_Excitation_CUDA::Free(List& l)
{
	void* ptrs[] = {l.d_sig, l.d_off, l.d_first, l.d_amp, l.d_delay};
	for (size_t n = 0; n < sizeof(ptrs) / sizeof(ptrs[0]); ++n)
		if (ptrs[n]) cudaFree(ptrs[n]);
	l = List();
}

std::string Engine_Ext_Excitation_CUDA::GetExtensionName() const
{
	return Engine_Extension::GetExtensionName() + " (GPU)";
}

void Engine_Ext_Excitation_CUDA::Apply(float* field, const List& l)
{
	if (l.groups == 0)
		return;
	const int numTS = (int)m_EngCuda->GetNumberOfTimesteps();
	// same as the host version: without a signal period the period is longer than any time step
	int p = (m_PeriodSteps > 0) ? m_PeriodSteps : numTS + 1;
	if (p <= 0) p = 1;
	m_EngCuda->DeviceBegin();
	EXC_CUDA_CHECK(Exc_Launch(field, l.d_off, l.d_first, l.d_amp, l.d_delay, l.groups, l.d_sig, numTS, p, m_Length));
	m_EngCuda->DeviceEnd();
}

void Engine_Ext_Excitation_CUDA::Apply2Voltages()
{
	Apply((float*)m_EngCuda->d_volt, m_Volt);
}

void Engine_Ext_Excitation_CUDA::Apply2Current()
{
	Apply((float*)m_EngCuda->d_curr, m_Curr);
}
