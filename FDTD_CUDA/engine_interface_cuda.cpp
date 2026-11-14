#include "engine_interface_cuda.h"
#include "engine_cuda.h"

#include <cstdlib>
#include <cmath>
#include <iostream>
#include <iomanip>

Engine_Interface_CUDA::Engine_Interface_CUDA(Operator* op) : Engine_Interface_FDTD(op)
{
}

Engine_Interface_CUDA::~Engine_Interface_CUDA()
{
}

double Engine_Interface_CUDA::CalcFastEnergy() const
{
	Engine_CUDA* eng = dynamic_cast<Engine_CUDA*>(m_Eng);
	if (eng == NULL)
		return Engine_Interface_FDTD::CalcFastEnergy();

	double E_energy = 0.0, H_energy = 0.0;
	eng->CalcEnergySums(E_energy, H_energy);
	const double gpu = __EPS0__ * E_energy + __MUE0__ * H_energy;

	// OPENEMS_CUDA_CHECK_ENERGY=1: compare with the host summation (slow, for testing only)
	if (getenv("OPENEMS_CUDA_CHECK_ENERGY") != NULL)
	{
		const double host = Engine_Interface_FDTD::CalcFastEnergy();
		const double rel = (host != 0.0) ? std::fabs(gpu - host) / std::fabs(host) : std::fabs(gpu);
		std::cout << std::setprecision(10) << "CUDA energy check at timestep " << eng->GetNumberOfTimesteps()
		          << ": gpu=" << gpu << " host=" << host << " rel.diff=" << rel << (rel < 1e-5 ? "  OK" : "  MISMATCH") << std::endl;
	}
	return gpu;
}
