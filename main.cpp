/*
*	Copyright (C) 2010 Thorsten Liebig (Thorsten.Liebig@gmx.de)
*
*	This program is free software: you can redistribute it and/or modify
*	it under the terms of the GNU General Public License as published by
*	the Free Software Foundation, either version 3 of the License, or
*	(at your option) any later version.
*
*	This program is distributed in the hope that it will be useful,
*	but WITHOUT ANY WARRANTY; without even the implied warranty of
*	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*	GNU General Public License for more details.
*
*	You should have received a copy of the GNU General Public License
*	along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <stdio.h>
#include <stdlib.h>
#include <iostream>
#include <exception>
#include <fstream>
#include <sstream>

#ifdef MPI_SUPPORT
#include "mpi.h"
#include "FDTD/openems_fdtd_mpi.h"
#else
#include "openems.h"
#endif

#include "tools/global.h"

#ifndef GIT_VERSION
#define GIT_VERSION "unknown:compiled@" __DATE__
#endif

using namespace std;

int main(int argc, char *argv[])
{
#ifdef MPI_SUPPORT
	//init MPI
	MPI::Init(argc,argv);
	openEMS_FDTD_MPI FDTD(false);
#else
	openEMS FDTD;
#endif

#ifdef MPI_SUPPORT
	openEMS_FDTD_MPI::WelcomeScreen();
#else
	openEMS::WelcomeScreen();
#endif

	if (argc<=1)
	{
		openEMS::showUsage();
		exit(-1);
	}

	if (argc>=3)
	{
		for (int n=2; n<argc; ++n)
		{
			if ( (!FDTD.parseCommandLineArgument(argv[n])) && (!g_settings.parseCommandLineArgument(argv[n])))
				cout << "openEMS - unknown argument: " << argv[n] << endl;
		}
	}

	int EC = FDTD.ParseFDTDSetup(argv[1]);
	if(!EC) {
	  cerr << "openEMS - ParseFDTDSetup failed." << endl;
	  exit(1);
	}
	// Errors thrown by an engine (e.g. a failed CUDA call) must end the run with a clear message and
	// a non-zero exit code instead of an uncaught exception (abort, crash dialog on Windows).
	try
	{
		EC = FDTD.SetupFDTD();
	}
	catch (const std::exception& e)
	{
		cerr << "openEMS - Error during setup: " << e.what() << endl;
		exit(3);
	}
	catch (...)
	{
		cerr << "openEMS - Error during setup: unknown exception" << endl;
		exit(3);
	}
	if (EC) exit(EC);

	try
	{
		FDTD.RunFDTD();
	}
	catch (const std::exception& e)
	{
		cerr << "openEMS - Error during the simulation: " << e.what() << endl;
		cerr << "openEMS - The simulation was aborted. Result files written so far are incomplete: do not use them." << endl;
		exit(4);
	}
	catch (...)
	{
		cerr << "openEMS - Error during the simulation: unknown exception" << endl;
		cerr << "openEMS - The simulation was aborted. Result files written so far are incomplete: do not use them." << endl;
		exit(4);
	}

#ifdef MPI_SUPPORT
	FDTD.Reset(); //make sure everything is cleaned-up before calling MPI::Finalize()
	MPI::Finalize();
#endif

	exit(0);
}
