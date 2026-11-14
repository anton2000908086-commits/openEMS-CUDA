#include "operator_cuda.h"
#include "engine_cuda.h"

#include <assert.h>
#include <stdexcept>
#include <string>

Operator_CUDA* Operator_CUDA::New(unsigned int cuda_device_number)
{
	cout << "Create FDTD operator (CUDA)" << endl;
	Operator_CUDA* op = new Operator_CUDA();
	op->setCUDAdevice(cuda_device_number);
	op->Init();
	return op;
}

Engine* Operator_CUDA::CreateEngine()
{
	m_Engine = Engine_CUDA::New(this, m_cuda_device_number);
	return m_Engine;
}

void Operator_CUDA::setCUDAdevice(unsigned int cuda_device_number) {
	m_cuda_device_number = cuda_device_number;
}

void Operator_CUDA::InitOperator()
{
	// fail early with a clear message if the requested GPU does not exist
	int nDevices = 0;
	cudaError_t err = cudaGetDeviceCount(&nDevices);
	if (err != cudaSuccess)
		throw std::runtime_error(std::string("CUDA error: ") + cudaGetErrorString(err));
	if (nDevices <= 0)
		throw std::runtime_error("No CUDA devices found");
	if (m_cuda_device_number >= (unsigned int)nDevices)
		throw std::runtime_error("CUDA device number out of range");

	// Check that CUDA_VECTOR is the correct type
	assert(sizeof(CUDA_VECTOR) == sizeof(FDTD_FLOAT)*4);

	const size_t numCells = (size_t)numLines[0] * numLines[1] * numLines[2];
	const float4 zero = {0.0f, 0.0f, 0.0f, 0.0f};
	m_vv.assign(numCells, zero);
	m_vi.assign(numCells, zero);
	m_ii.assign(numCells, zero);
	m_iv.assign(numCells, zero);
}

void Operator_CUDA::Delete()
{
	std::vector<float4>().swap(m_vv);
	std::vector<float4>().swap(m_vi);
	std::vector<float4>().swap(m_ii);
	std::vector<float4>().swap(m_iv);

	Operator::Delete();
}
