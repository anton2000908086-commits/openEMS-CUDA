#ifndef ENGINE_EXT_EXCITATION_CUDA_H
#define ENGINE_EXT_EXCITATION_CUDA_H

#include <string>
#include "extensions/engine_extension.h"
#include "excitation_kernels_cuda.h"

class Operator_Ext_Excitation;
class Engine_CUDA;

//! Soft voltage/current excitation on the GPU. Signal, cell offsets, amplitudes and delays are
//! uploaded once; per time step only the step number is passed to the kernel.
/*!
  Entries that address the same field value (possible with overlapping wires/curves) are grouped on the
  host, in their original order, and summed by one thread in that order: the result is deterministic
  and equals the host version.
*/
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

	//! one excitation list (voltage or current) on the GPU
	struct List
	{
		unsigned int entries;        //!< number of excitation entries
		unsigned int groups;         //!< number of distinct field values they address
		float* d_sig;
		unsigned long long* d_off;   //!< per group: 4*cell + component
		unsigned int* d_first;       //!< groups+1 values: group g owns the entries [first[g], first[g+1])
		float* d_amp;                //!< per entry, ordered by group
		unsigned int* d_delay;       //!< per entry, ordered by group
		List() : entries(0), groups(0), d_sig(NULL), d_off(NULL), d_first(NULL), d_amp(NULL), d_delay(NULL) {}
	};
	List m_Volt, m_Curr;

	void Build(List& l, const float* signal, unsigned int count, unsigned int* const index[3],
	           const unsigned short* dir, const float* amp, const unsigned int* delay, const char* name);
	void Free(List& l);
	void Apply(float* field, const List& l);
};

#endif // ENGINE_EXT_EXCITATION_CUDA_H
