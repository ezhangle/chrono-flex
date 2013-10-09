#include <algorithm>
#include <vector>
#include "include.cuh"
#include "ANCFSystem.cuh"

#include <cusp/io/matrix_market.h>

// linear operator y = A*x
class stencil: public cusp::linear_operator<double, cusp::device_memory> {
public:
	typedef cusp::linear_operator<double, cusp::device_memory> super;

	int N;
	DeviceView massMatrix;
	DeviceView stiffnessMatrix;
	DeviceValueArrayView temp;

// constructor
	stencil(int N, DeviceView mass, DeviceView stiffness,
			DeviceValueArrayView tempVector) :
			super(N, N), N(N) {
		massMatrix = mass;
		stiffnessMatrix = stiffness;
		temp = tempVector;
	}

// linear operator y = A*x
	template<typename VectorType1, typename VectorType2>
	void operator()(const VectorType1& x, VectorType2& y) const {
// obtain a raw pointer to device memory
		cusp::multiply(massMatrix, x, temp);
		cusp::multiply(stiffnessMatrix, x, y);
		cusp::blas::axpy(temp, y, 1);
	}
};

ANCFSystem::ANCFSystem() {

	// spike stuff
	partitions = 1;
	spike::Options  opts;
	opts.safeFactorization = true;
	mySolver = new SpikeSolver(partitions,opts);
	mySpmv = new SpmvFunctor(lhs);
	useSpike = false;
	// end spike stuff

	this->timeIndex = 0;
	this->time = 0;
	this->h = 0.001;
	alphaHHT = -.1;
	betaHHT = (1 - alphaHHT) * (1 - alphaHHT) * .25;
	gammaHHT = 0.5 - alphaHHT;
	tol = 1e-7;
	timeToSimulate = 0;
	simTime = 0;
	fullJacobian = 1;

	wt3.push_back(5.0 / 9.0);
	wt3.push_back(8.0 / 9.0);
	wt3.push_back(5.0 / 9.0);

	pt3.push_back(-sqrt(3.0 / 5.0));
	pt3.push_back(0.0);
	pt3.push_back(sqrt(3.0 / 5.0));

	wt5.push_back((322. - 13. * sqrt(70.)) / 900.);
	wt5.push_back((322. + 13. * sqrt(70.)) / 900.);
	wt5.push_back(128. / 225.);
	wt5.push_back((322. + 13. * sqrt(70.)) / 900.);
	wt5.push_back((322. - 13. * sqrt(70.)) / 900.);

	pt5.push_back(-(sqrt(5. + 2. * sqrt(10. / 7.))) / 3.);
	pt5.push_back(-(sqrt(5. - 2. * sqrt(10. / 7.))) / 3.);
	pt5.push_back(0.);
	pt5.push_back((sqrt(5. - 2. * sqrt(10. / 7.))) / 3.);
	pt5.push_back((sqrt(5. + 2. * sqrt(10. / 7.))) / 3.);

	numCollisions = 0;
	numCollisionsSphere = 0;
	numContactPoints = 5;
	coefRestitution = .3;
	frictionCoef = .3;
	fileIndex = 0;

	// set up position files
	char filename1[100];
	char filename2[100];
	char filename3[100];
	sprintf(filename1, "position.dat");
	resultsFile1.open(filename1);
	sprintf(filename2, "energy.dat");
	resultsFile2.open(filename2);
	sprintf(filename3, "reactions.dat");
	resultsFile3.open(filename3);
}

double ANCFSystem::getCurrentTime()
{
	return time;
}
double ANCFSystem::getSimulationTime()
{
	return simTime;
}
double ANCFSystem::getTimeStep()
{
	return h;
}
double ANCFSystem::getTolerance()
{
	return tol;
}
int ANCFSystem::setSimulationTime(double simTime)
{
	this->simTime = simTime;
	return 0;
}
int ANCFSystem::setTimeStep(double h)
{
	this->h = h;
	return 0;
}
int ANCFSystem::setTolerance(double tolerance)
{
	this->tol = tolerance;
	return 0;
}
int ANCFSystem::getTimeIndex()
{
	return this->timeIndex;
}
int ANCFSystem::setPartitions(int partitions)
{
	spike::Options  opts;
	opts.safeFactorization = true;
	mySolver = new SpikeSolver(partitions,opts);
}

vector<float3> addMassMatrix(double rho, double A, double l)
{
		vector<float3> massNew;
		float3 massEntry;
		massEntry.x = 0;
		massEntry.y = 0;
		massEntry.z = 0.13e2 / 0.35e2 * rho * A * l;
		massNew.push_back(massEntry);
		massEntry.x = 0;
		massEntry.y = 3;
		massEntry.z = 0.11e2 / 0.210e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 0;
		massEntry.y = 6;
		massEntry.z = 0.9e1 / 0.70e2 * rho * A * l;
		massNew.push_back(massEntry);
		massEntry.x = 0;
		massEntry.y = 9;
		massEntry.z = -0.13e2 / 0.420e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 1;
		massEntry.y = 1;
		massEntry.z = 0.13e2 / 0.35e2 * rho * A * l;
		massNew.push_back(massEntry);
		massEntry.x = 1;
		massEntry.y = 4;
		massEntry.z = 0.11e2 / 0.210e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 1;
		massEntry.y = 7;
		massEntry.z = 0.9e1 / 0.70e2 * rho * A * l;
		massNew.push_back(massEntry);
		massEntry.x = 1;
		massEntry.y = 10;
		massEntry.z = -0.13e2 / 0.420e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 2;
		massEntry.y = 2;
		massEntry.z = 0.13e2 / 0.35e2 * rho * A * l;
		massNew.push_back(massEntry);
		massEntry.x = 2;
		massEntry.y = 5;
		massEntry.z = 0.11e2 / 0.210e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 2;
		massEntry.y = 8;
		massEntry.z = 0.9e1 / 0.70e2 * rho * A * l;
		massNew.push_back(massEntry);
		massEntry.x = 2;
		massEntry.y = 11;
		massEntry.z = -0.13e2 / 0.420e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 3;
		massEntry.y = 0;
		massEntry.z = 0.11e2 / 0.210e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 3;
		massEntry.y = 3;
		massEntry.z = rho * A * l * l * l / 0.105e3;
		massNew.push_back(massEntry);
		massEntry.x = 3;
		massEntry.y = 6;
		massEntry.z = 0.13e2 / 0.420e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 3;
		massEntry.y = 9;
		massEntry.z = -rho * A * l * l * l / 0.140e3;
		massNew.push_back(massEntry);
		massEntry.x = 4;
		massEntry.y = 1;
		massEntry.z = 0.11e2 / 0.210e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 4;
		massEntry.y = 4;
		massEntry.z = rho * A * l * l * l / 0.105e3;
		massNew.push_back(massEntry);
		massEntry.x = 4;
		massEntry.y = 7;
		massEntry.z = 0.13e2 / 0.420e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 4;
		massEntry.y = 10;
		massEntry.z = -rho * A * l * l * l / 0.140e3;
		massNew.push_back(massEntry);
		massEntry.x = 5;
		massEntry.y = 2;
		massEntry.z = 0.11e2 / 0.210e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 5;
		massEntry.y = 5;
		massEntry.z = rho * A * l * l * l / 0.105e3;
		massNew.push_back(massEntry);
		massEntry.x = 5;
		massEntry.y = 8;
		massEntry.z = 0.13e2 / 0.420e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 5;
		massEntry.y = 11;
		massEntry.z = -rho * A * l * l * l / 0.140e3;
		massNew.push_back(massEntry);
		massEntry.x = 6;
		massEntry.y = 0;
		massEntry.z = 0.9e1 / 0.70e2 * rho * A * l;
		massNew.push_back(massEntry);
		massEntry.x = 6;
		massEntry.y = 3;
		massEntry.z = 0.13e2 / 0.420e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 6;
		massEntry.y = 6;
		massEntry.z = 0.13e2 / 0.35e2 * rho * A * l;
		massNew.push_back(massEntry);
		massEntry.x = 6;
		massEntry.y = 9;
		massEntry.z = -0.11e2 / 0.210e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 7;
		massEntry.y = 1;
		massEntry.z = 0.9e1 / 0.70e2 * rho * A * l;
		massNew.push_back(massEntry);
		massEntry.x = 7;
		massEntry.y = 4;
		massEntry.z = 0.13e2 / 0.420e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 7;
		massEntry.y = 7;
		massEntry.z = 0.13e2 / 0.35e2 * rho * A * l;
		massNew.push_back(massEntry);
		massEntry.x = 7;
		massEntry.y = 10;
		massEntry.z = -0.11e2 / 0.210e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 8;
		massEntry.y = 2;
		massEntry.z = 0.9e1 / 0.70e2 * rho * A * l;
		massNew.push_back(massEntry);
		massEntry.x = 8;
		massEntry.y = 5;
		massEntry.z = 0.13e2 / 0.420e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 8;
		massEntry.y = 8;
		massEntry.z = 0.13e2 / 0.35e2 * rho * A * l;
		massNew.push_back(massEntry);
		massEntry.x = 8;
		massEntry.y = 11;
		massEntry.z = -0.11e2 / 0.210e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 9;
		massEntry.y = 0;
		massEntry.z = -0.13e2 / 0.420e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 9;
		massEntry.y = 3;
		massEntry.z = -rho * A * l * l * l / 0.140e3;
		massNew.push_back(massEntry);
		massEntry.x = 9;
		massEntry.y = 6;
		massEntry.z = -0.11e2 / 0.210e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 9;
		massEntry.y = 9;
		massEntry.z = rho * A * l * l * l / 0.105e3;
		massNew.push_back(massEntry);
		massEntry.x = 10;
		massEntry.y = 1;
		massEntry.z = -0.13e2 / 0.420e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 10;
		massEntry.y = 4;
		massEntry.z = -rho * A * l * l * l / 0.140e3;
		massNew.push_back(massEntry);
		massEntry.x = 10;
		massEntry.y = 7;
		massEntry.z = -0.11e2 / 0.210e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 10;
		massEntry.y = 10;
		massEntry.z = rho * A * l * l * l / 0.105e3;
		massNew.push_back(massEntry);
		massEntry.x = 11;
		massEntry.y = 2;
		massEntry.z = -0.13e2 / 0.420e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 11;
		massEntry.y = 5;
		massEntry.z = -rho * A * l * l * l / 0.140e3;
		massNew.push_back(massEntry);
		massEntry.x = 11;
		massEntry.y = 8;
		massEntry.z = -0.11e2 / 0.210e3 * rho * A * l * l;
		massNew.push_back(massEntry);
		massEntry.x = 11;
		massEntry.y = 11;
		massEntry.z = rho * A * l * l * l / 0.105e3;
		massNew.push_back(massEntry);

	return massNew;
}

int ANCFSystem::addParticle(Particle* particle)
{
	//add the element
	particle->setParticleIndex(particles.size());
	this->particles.push_back(*particle);

	MaterialParticle material;
	material.E = particle->getElasticModulus();
	material.nu = particle->getNu();
	material.mass = particle->getMass();
	material.massInverse = 1.0/particle->getMass();
	material.r = particle->getRadius();
	material.numContactPoints = 1;
	this->pMaterials_h.push_back(material);

	// update p
	float3 pos0 = particle->getInitialPosition();
	pParticle_h.push_back(pos0.x);
	pParticle_h.push_back(pos0.y);
	pParticle_h.push_back(pos0.z);

	// update v
	float3 vel0 = particle->getInitialVelocity();
	vParticle_h.push_back(vel0.x);
	vParticle_h.push_back(vel0.y);
	vParticle_h.push_back(vel0.z);

	for(int i=0;i<3;i++)
	{
		aParticle_h.push_back(0.0);
		fParticle_h.push_back(0.0);
	}

	return particles.size();
}

int ANCFSystem::addElement(Element* element)
{
	//add the element
	element->setElementIndex(elements.size());
	this->elements.push_back(*element);

	Material material;
	material.E = element->getElasticModulus();
	material.l = element->getLength_l();
	material.nu = element->getNu();
	material.rho = element->getDensity();
	material.r = element->getRadius();
	material.numContactPoints = numContactPoints;
	this->materials.push_back(material);

	// update p
	Node node = element->getNode0();
	p_h.push_back(node.x);
	p_h.push_back(node.y);
	p_h.push_back(node.z);
	p_h.push_back(node.dx1);
	p_h.push_back(node.dy1);
	p_h.push_back(node.dz1);
	node = element->getNode1();
	p_h.push_back(node.x);
	p_h.push_back(node.y);
	p_h.push_back(node.z);
	p_h.push_back(node.dx1);
	p_h.push_back(node.dy1);
	p_h.push_back(node.dz1);

	for(int i=0;i<12;i++)
	{
		e_h.push_back(0.0);
		v_h.push_back(0.0);
		a_h.push_back(0.0);
		anew_h.push_back(0.0);
		lhsVec_h.push_back(0.0);
		lhsVecStiffness_h.push_back(0.0);
		fint_h.push_back(0.0);
		fcon_h.push_back(0.0);
		fapp_h.push_back(0.0);
		phiqlam_h.push_back(0.0);
		delta_h.push_back(0.0);
		strainDerivative_h.push_back(0.0);
		//fext_h.push_back(0);
	}
	strain_h.push_back(0.0);

	for(int i=0;i<4;i++)
	{
		Sx_h.push_back(0.0);
		Sxx_h.push_back(0.0);
	}

	//update other vectors (no initial velocity or acceleration)
	double r = element->getRadius();
	double a = element->getLength_l();
	double rho = element->getDensity();
	double A = PI*r*r;
		
	// update external force vector (gravity)
	fext_h.push_back(rho * A * a * GRAVITYx / 0.2e1);
	fext_h.push_back(rho * A * a * GRAVITYy / 0.2e1);
	fext_h.push_back(rho * A * a * GRAVITYz / 0.2e1);
	fext_h.push_back(rho * A * a * a * GRAVITYx / 0.12e2);
	fext_h.push_back(rho * A * a * a * GRAVITYy / 0.12e2);
	fext_h.push_back(rho * A * a * a * GRAVITYz / 0.12e2);
	fext_h.push_back(rho * A * a * GRAVITYx / 0.2e1);
	fext_h.push_back(rho * A * a * GRAVITYy / 0.2e1);
	fext_h.push_back(rho * A * a * GRAVITYz / 0.2e1);
	fext_h.push_back(-rho * A * a * a * GRAVITYx / 0.12e2);
	fext_h.push_back(-rho * A * a * a * GRAVITYy / 0.12e2);
	fext_h.push_back(-rho * A * a * a * GRAVITYz / 0.12e2);
	
	//add mass matrix
	vector<float3> mass = addMassMatrix(rho,A,a);

	for(int i=0;i<mass.size();i++)
	{
		lhsI_h.push_back(mass[i].x+12*(elements.size()-1));
		lhsJ_h.push_back(mass[i].y+12*(elements.size()-1));
		lhs_h.push_back(static_cast<double>(mass[i].z));

		massI_h.push_back(mass[i].x+12*(elements.size()-1));
		massJ_h.push_back(mass[i].y+12*(elements.size()-1));
		mass_h.push_back(static_cast<double>(mass[i].z));
	}

	for(int i=0;i<12;i++)
	{
		for(int j=0;j<12;j++)
		{
			stiffnessI_h.push_back(i+12*(elements.size()-1));
			stiffnessJ_h.push_back(j+12*(elements.size()-1));
			stiffness_h.push_back(0.0);
		}
	}

	return elements.size();
}

int ANCFSystem::addForce(Element* element, double xi, float3 force)
{
	int index = element->getElementIndex();
	int l = element->getLength_l();

	fapp_h = fapp_d;

	fapp_h[ 0+12*index] += (1 - 3 * xi * xi + 2 * pow( xi, 3)) * force.x;
	fapp_h[ 1+12*index] += (1 - 3 * xi * xi + 2 * pow( xi, 3)) * force.y;
	fapp_h[ 2+12*index] += (1 - 3 * xi * xi + 2 * pow( xi, 3)) * force.z;
	fapp_h[ 3+12*index] += l * (xi - 2 * xi * xi + pow( xi, 3)) * force.x;
	fapp_h[ 4+12*index] += l * (xi - 2 * xi * xi + pow( xi, 3)) * force.y;
	fapp_h[ 5+12*index] += l * (xi - 2 * xi * xi + pow( xi, 3)) * force.z;
	fapp_h[ 6+12*index] += (3 * xi * xi - 2 * pow( xi, 3)) * force.x;
	fapp_h[ 7+12*index] += (3 * xi * xi - 2 * pow( xi, 3)) * force.y;
	fapp_h[ 8+12*index] += (3 * xi * xi - 2 * pow( xi, 3)) * force.z;
	fapp_h[ 9+12*index] += l * (-xi * xi + pow( xi, 3)) * force.x;
	fapp_h[10+12*index] += l * (-xi * xi + pow( xi, 3)) * force.y;
	fapp_h[11+12*index] += l * (-xi * xi + pow( xi, 3)) * force.z;

	fapp_d = fapp_h;

	return 0;
}

int ANCFSystem::clearAppliedForces()
{
	thrust::fill(fapp_d.begin(),fapp_d.end(),0.0); //Clear internal forces
}

int ANCFSystem::updatePhiq()
{
	//printf("updatePhiq1\n");
	for(int i=0;i<constraints.size();i++)
	{
		Constraint constraint = constraints[i];

		phiqJ_h.push_back(i);
		phiqI_h.push_back(constraint.dofLoc.x);
		phiq_h.push_back(1.0);

		if(constraint.nodeNum2!=-1)
		{
			phiqJ_h.push_back(i);
			phiqI_h.push_back(constraint.dofLoc.y);
			phiq_h.push_back(-1.0);
		}
	}

	//printf("updatePhiq2\n");
	phiqI_d = phiqI_h;
	phiqJ_d = phiqJ_h;
	phiq_d = phiq_h;

	thrust::device_ptr<int> wrapped_device_I(CASTI1(phiqI_d));
	DeviceIndexArrayView row_indices = DeviceIndexArrayView(wrapped_device_I, wrapped_device_I + phiqI_d.size());

	thrust::device_ptr<int> wrapped_device_J(CASTI1(phiqJ_d));
	DeviceIndexArrayView column_indices = DeviceIndexArrayView(wrapped_device_J, wrapped_device_J + phiqJ_d.size());

	thrust::device_ptr<double> wrapped_device_V(CASTD1(phiq_d));
	DeviceValueArrayView values = DeviceValueArrayView(wrapped_device_V, wrapped_device_V + phiq_d.size());

	phiq = DeviceView(12*elements.size(), constraints.size(), phiq_d.size(), row_indices, column_indices, values);
	phiq.sort_by_row();

	return 0;
}

__global__ void calculateRHSlower(double* phi, double* p, double* phi0, double factor, int2* constraintPairs, int numConstraints)
{
	int i = threadIdx.x+blockIdx.x*blockDim.x;

	if(i<numConstraints)
	{
		int2 constraintPair = constraintPairs[i];
		if(constraintPair.y == -1)
		{
			phi[i] = factor*(p[constraintPair.x]-phi0[i]);
		}
		else
		{
			phi[i] = factor*(p[constraintPair.x]-p[constraintPair.y]-phi0[i]);
		}
		__syncthreads();
	}
}

int ANCFSystem::updatePhi()
{
	calculateRHSlower<<<dimGridConstraint,dimBlockConstraint>>>(CASTD1(phi_d), CASTD1(pnew_d), CASTD1(phi0_d), 1.0/(betaHHT*h*h), CASTI2(constraintPairs_d), constraints.size());

	return 0;
}

__global__ void updateParticleDynamics_GPU(double h, double* a, double* v, double* p, double* f, MaterialParticle* materials, int numParticles)
{
	int i = threadIdx.x+blockIdx.x*blockDim.x;

	if(i<numParticles)
	{
		a = &a[3*i];
		v = &v[3*i];
		p = &p[3*i];
		f = &f[3*i];
		MaterialParticle material = materials[i];

		a[0] = material.massInverse*f[0]+GRAVITYx;
		a[1] = material.massInverse*f[1]+GRAVITYy;
		a[2] = material.massInverse*f[2]+GRAVITYz;

		for(int j=0;j<3;j++)
		{
			v[j] += h*a[j];
			p[j] += h*v[j];
		}
	}
}

int ANCFSystem::updateParticleDynamics()
{
	updateParticleDynamics_GPU<<<dimGridParticles,dimBlockParticles>>>(h,CASTD1(aParticle_d), CASTD1(vParticle_d), CASTD1(pParticle_d), CASTD1(fParticle_d), CASTMP(pMaterials_d), particles.size());

	return 0;
}

int ANCFSystem::calculateInitialPhi()
{
	for(int i=0;i<constraints.size();i++) phi0_h.push_back(0);
	for(int i=0;i<constraints.size();i++)
	{
		Constraint constraint = constraints[i];

		if(constraint.nodeNum2 == -1)
		{
			phi0_h[i] = p_h[constraint.dofLoc.x];
		}
		else
		{
			phi0_h[i] = p_h[constraint.dofLoc.x]-p_h[constraint.dofLoc.y];
		}
	}

	return 0;
}

int ANCFSystem::initializeDevice()
{
	pMaterials_d = pMaterials_h;
	pParticle_d = pParticle_h;
	vParticle_d = vParticle_h;
	aParticle_d = aParticle_h;
	fParticle_d = fParticle_h;

	materials_d = materials;
	strainDerivative_d = strainDerivative_h;
	curvatureDerivative_d = strainDerivative_h;
	strain_d = strain_h;
	Sx_d = Sx_h;
	Sxx_d = Sxx_h;

	e_d = e_h;
	p_d = p_h;
	v_d = v_h;
	a_d = a_h;
	pnew_d = p_h;
	vnew_d = v_h;
	anew_d = anew_h;

	// solver variables!
	lhsVec_d = lhsVec_h;
	lhsVecStiffness_d = lhsVecStiffness_h;
	rcg_d = lhsVec_h;
	pcg_d = lhsVec_h;
	rhatcg_d = lhsVec_h;
	phatcg_d = lhsVec_h;
	residual_d = lhsVec_h;
	// end solver variables

	fext_d = fext_h;
	fint_d = fint_h;
	fapp_d = fapp_h;
	fcon_d = fcon_h;
	phi_d = phi_h;
	phi0_d = phi0_h;
	phiqlam_d = phiqlam_h;
	delta_d = delta_h;
	constraintPairs_d = constraintPairs_h;

	lhsI_d = lhsI_h;
	lhsJ_d = lhsJ_h;
	lhs_d = lhs_h;

	constraintsI_d = constraintsI_h;
	constraintsJ_d = constraintsJ_h;
	constraints_d = constraints_h;

	thrust::device_ptr<double> wrapped_device_e(CASTD1(e_d));
	thrust::device_ptr<double> wrapped_device_p(CASTD1(p_d));
	thrust::device_ptr<double> wrapped_device_v(CASTD1(v_d));
	thrust::device_ptr<double> wrapped_device_a(CASTD1(a_d));
	thrust::device_ptr<double> wrapped_device_pnew(CASTD1(pnew_d));
	thrust::device_ptr<double> wrapped_device_vnew(CASTD1(vnew_d));
	thrust::device_ptr<double> wrapped_device_anew(CASTD1(anew_d));
	thrust::device_ptr<double> wrapped_device_lhsVec(CASTD1(lhsVec_d));
	thrust::device_ptr<double> wrapped_device_lhsVecStiffness(CASTD1(lhsVecStiffness_d));

	// solver variables
	thrust::device_ptr<double> wrapped_device_rcg(CASTD1(rcg_d));
	thrust::device_ptr<double> wrapped_device_pcg(CASTD1(pcg_d));
	thrust::device_ptr<double> wrapped_device_rhatcg(CASTD1(rhatcg_d));
	thrust::device_ptr<double> wrapped_device_phatcg(CASTD1(phatcg_d));
	thrust::device_ptr<double> wrapped_device_residual(CASTD1(residual_d));
	// end solver variables

	thrust::device_ptr<double> wrapped_device_fext(CASTD1(fext_d));
	thrust::device_ptr<double> wrapped_device_fint(CASTD1(fint_d));
	thrust::device_ptr<double> wrapped_device_fapp(CASTD1(fapp_d));
	thrust::device_ptr<double> wrapped_device_fcon(CASTD1(fcon_d));
	thrust::device_ptr<double> wrapped_device_phi(CASTD1(phi_d));
	thrust::device_ptr<double> wrapped_device_phi0(CASTD1(phi0_d));
	thrust::device_ptr<double> wrapped_device_phiqlam(CASTD1(phiqlam_d));
	thrust::device_ptr<double> wrapped_device_delta(CASTD1(delta_d));

	eAll = DeviceValueArrayView(wrapped_device_e, wrapped_device_e + e_d.size());
	eTop = DeviceValueArrayView(wrapped_device_e, wrapped_device_e + 12*elements.size());
	eBottom = DeviceValueArrayView(wrapped_device_e + 12*elements.size(), wrapped_device_e + e_d.size());
	p = DeviceValueArrayView(wrapped_device_p, wrapped_device_p + p_d.size());
	v = DeviceValueArrayView(wrapped_device_v, wrapped_device_v + v_d.size());
	a = DeviceValueArrayView(wrapped_device_a, wrapped_device_a + a_d.size());
	pnew = DeviceValueArrayView(wrapped_device_pnew, wrapped_device_pnew + pnew_d.size());
	vnew = DeviceValueArrayView(wrapped_device_vnew, wrapped_device_vnew + vnew_d.size());
	anewAll = DeviceValueArrayView(wrapped_device_anew, wrapped_device_anew + anew_d.size());
	anew = DeviceValueArrayView(wrapped_device_anew, wrapped_device_anew + 12*elements.size());
	lhsVec = DeviceValueArrayView(wrapped_device_lhsVec, wrapped_device_lhsVec + lhsVec_d.size());
	lhsVecStiffness = DeviceValueArrayView(wrapped_device_lhsVecStiffness, wrapped_device_lhsVecStiffness + lhsVecStiffness_d.size());

	// solver variables
	rcg = DeviceValueArrayView(wrapped_device_rcg, wrapped_device_rcg + rcg_d.size());
	pcg = DeviceValueArrayView(wrapped_device_pcg, wrapped_device_pcg + pcg_d.size());
	rhatcg = DeviceValueArrayView(wrapped_device_rhatcg, wrapped_device_rhatcg + rhatcg_d.size());
	phatcg = DeviceValueArrayView(wrapped_device_phatcg, wrapped_device_phatcg + phatcg_d.size());
	residual = DeviceValueArrayView(wrapped_device_residual, wrapped_device_residual + residual_d.size());
	// end solver variables

	lambda = DeviceValueArrayView(wrapped_device_anew + 12*elements.size(), wrapped_device_anew + anew_d.size());
	fext = DeviceValueArrayView(wrapped_device_fext, wrapped_device_fext + fext_d.size());
	fint = DeviceValueArrayView(wrapped_device_fint, wrapped_device_fint + fint_d.size());
	fapp = DeviceValueArrayView(wrapped_device_fapp, wrapped_device_fapp + fapp_d.size());
	fcon = DeviceValueArrayView(wrapped_device_fcon, wrapped_device_fcon + fcon_d.size());
	phi = DeviceValueArrayView(wrapped_device_phi, wrapped_device_phi + phi_d.size());
	phi0 = DeviceValueArrayView(wrapped_device_phi0, wrapped_device_phi0 + phi0_d.size());
	phiqlam = DeviceValueArrayView(wrapped_device_phiqlam, wrapped_device_phiqlam + phiqlam_d.size());
	delta = DeviceValueArrayView(wrapped_device_delta, wrapped_device_delta + delta_d.size());

	// create mass matrix using cusp library (shouldn't change)
	thrust::device_ptr<int> wrapped_device_I(CASTI1(lhsI_d));
	DeviceIndexArrayView row_indices = DeviceIndexArrayView(wrapped_device_I, wrapped_device_I + lhsI_d.size());

	thrust::device_ptr<int> wrapped_device_J(CASTI1(lhsJ_d));
	DeviceIndexArrayView column_indices = DeviceIndexArrayView(wrapped_device_J, wrapped_device_J + lhsJ_d.size());

	thrust::device_ptr<double> wrapped_device_V(CASTD1(lhs_d));
	DeviceValueArrayView values = DeviceValueArrayView(wrapped_device_V, wrapped_device_V + lhs_d.size());

	lhs = DeviceView(anew_d.size(), anew_d.size(), lhs_d.size(), row_indices, column_indices, values);
	lhs.sort_by_row();

	dimBlockConstraint.x = BLOCKDIMCONSTRAINT;
	dimGridConstraint.x = static_cast<int>(ceil((static_cast<double>(constraints.size()))/(static_cast<double>(BLOCKDIMCONSTRAINT))));

	dimBlockElement.x = BLOCKDIMELEMENT;
	dimGridElement.x = (int)ceil(((double)(elements.size()))/((double)BLOCKDIMELEMENT));

	dimBlockParticles.x = BLOCKDIMELEMENT;
	dimGridParticles.x = (int)ceil(((double)(particles.size()))/((double)BLOCKDIMELEMENT));

	dimBlockCollision.x = BLOCKDIMCOLLISION;
	dimGridCollision.x = (int)ceil(((double)(particles.size()))/((double)BLOCKDIMCOLLISION));

	return 0;
}

int ANCFSystem::createMass()
{
	massI_d = massI_h;
	massJ_d = massJ_h;
	mass_d = mass_h;

	// create mass matrix using cusp library (shouldn't change)
	thrust::device_ptr<int> wrapped_device_I(CASTI1(massI_d));
	DeviceIndexArrayView row_indices = DeviceIndexArrayView(wrapped_device_I, wrapped_device_I + massI_d.size());

	thrust::device_ptr<int> wrapped_device_J(CASTI1(massJ_d));
	DeviceIndexArrayView column_indices = DeviceIndexArrayView(wrapped_device_J, wrapped_device_J + massJ_d.size());

	thrust::device_ptr<double> wrapped_device_V(CASTD1(mass_d));
	DeviceValueArrayView values = DeviceValueArrayView(wrapped_device_V, wrapped_device_V + mass_d.size());

	mass = DeviceView(p_h.size(), p_h.size(), mass_d.size(), row_indices, column_indices, values);
	mass.sort_by_row();

	stiffnessI_d = stiffnessI_h;
	stiffnessJ_d = stiffnessJ_h;
	stiffness_d = stiffness_h;

	thrust::device_ptr<int> wrapped_device_I_S(CASTI1(stiffnessI_d));
	DeviceIndexArrayView row_indices_S = DeviceIndexArrayView(wrapped_device_I_S, wrapped_device_I_S + stiffnessI_d.size());

	thrust::device_ptr<int> wrapped_device_J_S(CASTI1(stiffnessJ_d));
	DeviceIndexArrayView column_indices_S = DeviceIndexArrayView(wrapped_device_J_S, wrapped_device_J_S + stiffnessJ_d.size());

	thrust::device_ptr<double> wrapped_device_V_S(CASTD1(stiffness_d));
	DeviceValueArrayView values_S = DeviceValueArrayView(wrapped_device_V_S, wrapped_device_V_S + stiffness_d.size());
	stiffness = DeviceView(12*elements.size()+constraints.size(),12*elements.size()+constraints.size(), stiffness_d.size(), row_indices_S, column_indices_S, values_S);

	return 0;
}

int ANCFSystem::initializeSystem()
{
	ANCFSystem::updatePhiq();
	ANCFSystem::calculateInitialPhi();
	ANCFSystem::createMass();

	for(int i=0;i<constraints.size();i++)
	{
		delta_h.push_back(0);
		e_h.push_back(0);
		anew_h.push_back(0);
		lhsVec_h.push_back(0);
		lhsVecStiffness_h.push_back(0);
		phi_h.push_back(0);
		constraintPairs_h.push_back(constraints[i].dofLoc);
	}

	// join phi_q to lhs
	for(int i=0;i<constraints.size();i++)
	{
		Constraint constraint = constraints[i];
		lhsI_h.push_back(i+12*elements.size());
		lhsJ_h.push_back(constraint.dofLoc.x);
		lhs_h.push_back(1.0);

		if(constraint.nodeNum2!=-1)
		{
			lhsI_h.push_back(i+12*elements.size());
			lhsJ_h.push_back(constraint.dofLoc.y);
			lhs_h.push_back(-1.0);
		}
	}

	// join phi_q' to lhs
	for(int i=0;i<constraints.size();i++)
	{
		Constraint constraint = constraints[i];
		lhsJ_h.push_back(i+12*elements.size());
		lhsI_h.push_back(constraint.dofLoc.x);
		lhs_h.push_back(1.0);

		if(constraint.nodeNum2!=-1)
		{
			lhsJ_h.push_back(i+12*elements.size());
			lhsI_h.push_back(constraint.dofLoc.y);
			lhs_h.push_back(-1.0);
		}
	}

	// Get constraints
	for(int i=0;i<constraints.size();i++)
	{
		Constraint constraint = constraints[i];
		constraintsI_h.push_back(i+12*elements.size());
		constraintsJ_h.push_back(constraint.dofLoc.x);
		constraints_h.push_back(1.0);

		if(constraint.nodeNum2!=-1)
		{
			constraintsI_h.push_back(i+12*elements.size());
			constraintsJ_h.push_back(constraint.dofLoc.y);
			constraints_h.push_back(-1.0);
		}
	}

	// join phi_q' to lhs
	for(int i=0;i<constraints.size();i++)
	{
		Constraint constraint = constraints[i];
		constraintsJ_h.push_back(i+12*elements.size());
		constraintsI_h.push_back(constraint.dofLoc.x);
		constraints_h.push_back(1.0);

		if(constraint.nodeNum2!=-1)
		{
			constraintsJ_h.push_back(i+12*elements.size());
			constraintsI_h.push_back(constraint.dofLoc.y);
			constraints_h.push_back(-1.0);
		}
	}

	initializeDevice();
	ANCFSystem::initializeBoundingBoxes_CPU();
	//detector.updateBoundingBoxes(aabb_data_d);
	detector.setBoundingBoxPointer(&aabb_data_d);
	detector.detectPossibleCollisions();

	ANCFSystem::updateInternalForces();

	//cusp::blas::axpy(fint,eTop,-1);
	cusp::blas::axpby(fext,fint,eTop,1,-1);

	// set stopping criteria:
	//  iteration_limit    = 100
	//  relative_tolerance = 1e-5
	cusp::default_monitor<double> monitor(eAll,1000,1e-7);

	// solve the linear system A * x = b with the Bi-Conjugate Gradient - Stable method
	cusp::krylov::cg(lhs, delta, eAll, monitor);

	// spike stuff
	mySolver->setup(lhs);
	// end spike stuff

	//ANCFSystem::saveLHS();
	//cusp::print(lhs);
	//cin.get();
	//int it_NK = ANCFSystem::solve_bicgstab();
	//cin.get();
	//cusp::multiply(lhsCSR,eAll,anewAll);
	//ANCFSystem::solve_cg();

	cusp::copy(delta,anewAll);
	cusp::copy(anew,a);
	cusp::copy(v,vnew);
	cusp::copy(p,pnew);

	ANCFSystem::updateParticleDynamics();

	return 0;
}

int ANCFSystem::getLeftHandSide(DeviceValueArrayView x)
{

	//cusp::print(lhs);
	//cin.get();
	cusp::multiply(lhs,x,lhsVec);
	//cusp::multiply(stiffness,x,lhsVecStiffness);
	//cusp::blas::axpy(lhsVecStiffness,lhsVec,1);

	return 0;
}

int ANCFSystem::solve_cg()
{
	thrust::fill(delta_d.begin(),delta_d.end(),0.0);
	ANCFSystem::getLeftHandSide(delta);
	cusp::blas::axpby(eAll,lhsVec,rcg,1,-1);
	cusp::copy(rcg,pcg);
	double rsold = cusp::blas::dot(rcg,rcg);
	double alpha = 0;
	double rsnew = 0;
	int iter = 0;
	for(int i=1;i<=12*elements.size()+constraints.size();i++)
	//while(1)
	{
		iter ++;

		ANCFSystem::getLeftHandSide(pcg);
		alpha = cusp::blas::dot(pcg,lhsVec);
		alpha = rsold/alpha;
		cusp::blas::axpy(pcg,delta,alpha);
		cusp::blas::axpy(lhsVec,rcg,-1*alpha);
		rsnew = cusp::blas::dot(rcg,rcg);
		if(sqrt(rsnew)<tol)
		{
			//printf("\n");
			return iter;
		}
		cusp::blas::axpby(rcg,pcg,pcg,1,rsnew/rsold);

		rsold = rsnew;
		//printf("%d %.13f\n",iter,sqrt(rsnew));
	}
	//printf("\n");
	return 12*elements.size()+constraints.size();
}

int ANCFSystem::solve_bicgstab()
{
	thrust::fill(delta_d.begin(),delta_d.end(),0.0);
	ANCFSystem::getLeftHandSide(delta);
	cusp::blas::axpby(eAll,lhsVec,rcg,1,-1);
	cusp::copy(rcg,rhatcg);
	double rho_old = 1;
	thrust::fill(pcg_d.begin(),pcg_d.end(),0.0);
	cusp::copy(pcg,phatcg);

	double rho;
	double beta;
	double alpha;
	double temp;

	int iter = 0;
	double norm;

	while(1)
	{
		iter ++;

		rho = cusp::blas::dot(rhatcg,rcg);
		beta = rho/rho_old;
		cusp::blas::axpby(rcg,pcg,pcg,1,beta);
		cusp::blas::axpby(rhatcg,phatcg,phatcg,1,beta);
		ANCFSystem::getLeftHandSide(pcg);
		temp = cusp::blas::dot(phatcg,lhsVec);
		alpha = rho/temp;
		cusp::blas::axpy(pcg,delta,alpha);

		ANCFSystem::getLeftHandSide(delta);
		cusp::blas::axpby(eAll,lhsVec,residual,1,-1);
		norm = cusp::blas::nrmmax(residual);

		//norm = cusp::blas::nrm2(pcg);
		if(norm<tol)
		{
			//printf("\n");
			return iter;
		}

		ANCFSystem::getLeftHandSide(pcg);
		cusp::blas::axpy(lhsVec,rcg,-1*alpha);
		ANCFSystem::getLeftHandSide(phatcg);
		cusp::blas::axpy(lhsVec,rhatcg,-1*alpha);

		// update!
		rho_old = rho;
		//printf("%d %.13f\n",iter,norm);
	}
	//printf("\n");
	return iter;
}

int ANCFSystem::DoTimeStep()
{
	cudaEvent_t start, stop;
	cudaEventCreate(&start);
	cudaEventCreate(&stop);
	cudaEventRecord(start, 0);

	double norm_e=1;
	double norm_d=1;
	int it = 0;

	ANCFSystem::updateParticleDynamics();

	// update q and q_dot for initial guess
	cusp::blas::axpbypcz(p,v,a,pnew,1,h,.5*h*h);
	cusp::blas::axpby(v,a,vnew,1,h);

	while(norm_e>tol&&norm_d>tol)
	{
		it++;

		ANCFSystem::updateInternalForces();
		ANCFSystem::updatePhi();

		cusp::multiply(phiq,lambda,phiqlam);
		cusp::multiply(mass,anew,eTop);
		cusp::blas::axpbypcz(eTop,fcon,fint,eTop,1,-1,1);
		cusp::blas::axpby(eTop,fext,eTop,1,-1);
		cusp::blas::axpy(phiqlam,eTop,1);
		cusp::blas::copy(phi,eBottom);

		// SOLVE THE LINEAR SYSTEM
		if(!useSpike)
		{
			if(fullJacobian)
			{
				// use full left-hand side matrix
				stencil lhsStencil(anewAll.size(), lhs, stiffness, lhsVec);

				// set stopping criteria:
				//  iteration_limit    = 100
				//  relative_tolerance = 1e-5
				cusp::default_monitor<double> monitor(eAll, 1000, tol);

				// solve the linear system A * x = b with the Bi-Conjugate Gradient - Stable method
				cusp::krylov::cg(lhsStencil, delta, eAll, monitor);

				cout << "Success: " << monitor.converged() << " Iterations: " << monitor.iteration_count() << " relResidualNorm: " << monitor.relative_tolerance() << endl;
			}
			else
			{
				// SOLVE USING CUSP CG
				// set stopping criteria:
				//  iteration_limit    = 100
				//  relative_tolerance = 1e-5
				cusp::default_monitor<double> monitor(eAll, 1000, tol);

				// solve the linear system A * x = b with the Bi-Conjugate Gradient - Stable method
				cusp::krylov::cg(lhs, delta, eAll, monitor);

				cout << "Success: " << monitor.converged() << " Iterations: " << monitor.iteration_count() << " relResidualNorm: " << monitor.relative_tolerance() << endl;
				//cin.get();
				// END SOLVE USING CUSP CG
			}
		}

		if(useSpike)
		{
			//SOLVE USING SPIKE
			cusp::blas::fill(delta,0);
			bool success = mySolver->solve(*mySpmv,eAll,delta);
			spike::Stats stats = mySolver->getStats();
			cout << "Success: " << success << " Iterations: " << stats.numIterations << " relResidualNorm: " << stats.relResidualNorm << endl;


	//		cusp::io::write_matrix_market_file(lhs, "lhs.txt");
			//cin.get();

	//		(*mySpmv)(delta,eAll);
	//		cusp::print(eAll);
	//		cin.get();
			//END SOLVE USING SPIKE
		}
		// END SOLVE THE LINEAR SYSTEM

		// update anew
		cusp::blas::axpy(delta,anewAll,-1);

		// update vnew
		cusp::blas::axpbypcz(v,a,anew,vnew,1,h*(1-gammaHHT),h*gammaHHT);

		// update pnew
		cusp::blas::axpbypcz(v,a,anew,pnew,h,h*h*.5*(1-2*betaHHT),h*h*.5*2*betaHHT);
		cusp::blas::axpy(p,pnew,1);

		// get norms
		norm_e = cusp::blas::nrm2(eAll)/pow((double)elements.size(),2);
		norm_d = cusp::blas::nrm2(delta)/pow((double)elements.size(),2);
		cout << norm_e << " " << norm_d << endl;
	}

	cusp::copy(anew,a);
	cusp::copy(vnew,v);
	cusp::copy(pnew,p);

	cudaEventRecord(stop, 0);
	cudaEventSynchronize(stop);
	float elapsedTime;
	cudaEventElapsedTime(&elapsedTime , start, stop);

	timeToSimulate+=elapsedTime/1000.0;

	p_h = p_d;
	v_h = v_d;
	pParticle_h = pParticle_d;
	vParticle_h = vParticle_d;

	//printf("Time: %f (it = %d, PTA pos = (%f, %.13f, %f)\n",this->getCurrentTime(),it,getXYZPosition(elements.size()-1,1).x,getXYZPosition(elements.size()-1,1).y,getXYZPosition(elements.size()-1,1).z);
	printf("Time: %f (Simulation time = %f ms, it = %d)\n",this->getCurrentTime(), elapsedTime,it);

	time+=h;
	timeIndex++;

	return 0;
}

float3 ANCFSystem::getXYZPosition(int elementIndex, double xi)
{
	double a = elements[elementIndex].getLength_l();
	double* p = CASTD1(p_h);
	p = &p[12*elementIndex];
	float3 pos;

	pos.x = (1 - 3 * xi * xi + 2 * pow(xi, 3)) * p[0] + a * (xi - 2 * xi * xi + pow(xi, 3)) * p[3] + (3 * xi * xi - 2 * pow(xi, 3)) * p[6] + a * (-xi * xi + pow(xi, 3)) * p[9];
	pos.y = (1 - 3 * xi * xi + 2 * pow(xi, 3)) * p[1] + a * (xi - 2 * xi * xi + pow(xi, 3)) * p[4] + (3 * xi * xi - 2 * pow(xi, 3)) * p[7] + a * (-xi * xi + pow(xi, 3)) * p[10];
	pos.z = (1 - 3 * xi * xi + 2 * pow(xi, 3)) * p[2] + a * (xi - 2 * xi * xi + pow(xi, 3)) * p[5] + (3 * xi * xi - 2 * pow(xi, 3)) * p[8] + a * (-xi * xi + pow(xi, 3)) * p[11];

	return pos;
}

float3 ANCFSystem::getXYZVelocity(int elementIndex, double xi)
{
	double a = elements[elementIndex].getLength_l();
	double* p = CASTD1(v_h);
	p = &p[12*elementIndex];
	float3 pos;

	pos.x = (1 - 3 * xi * xi + 2 * pow(xi, 3)) * p[0] + a * (xi - 2 * xi * xi + pow(xi, 3)) * p[3] + (3 * xi * xi - 2 * pow(xi, 3)) * p[6] + a * (-xi * xi + pow(xi, 3)) * p[9];
	pos.y = (1 - 3 * xi * xi + 2 * pow(xi, 3)) * p[1] + a * (xi - 2 * xi * xi + pow(xi, 3)) * p[4] + (3 * xi * xi - 2 * pow(xi, 3)) * p[7] + a * (-xi * xi + pow(xi, 3)) * p[10];
	pos.z = (1 - 3 * xi * xi + 2 * pow(xi, 3)) * p[2] + a * (xi - 2 * xi * xi + pow(xi, 3)) * p[5] + (3 * xi * xi - 2 * pow(xi, 3)) * p[8] + a * (-xi * xi + pow(xi, 3)) * p[11];

	return pos;
}


float3 ANCFSystem::getXYZPositionParticle(int index)
{
	return make_float3(pParticle_h[3*index],pParticle_h[3*index+1],pParticle_h[3*index+2]);
}

float3 ANCFSystem::getXYZVelocityParticle(int index)
{
	return make_float3(vParticle_h[3*index],vParticle_h[3*index+1],vParticle_h[3*index+2]);
}

int ANCFSystem::saveLHS()
{
	char filename[100];
	posFile.open("../lhs.dat");
	posFile << "symmetric" << endl;
	posFile << anew_h.size() << " " << anew_h.size() << " " << lhsI_h.size() << endl;
	for(int i=0;i<lhsI_h.size();i++)
	{
		posFile << lhsI_h[i] << " " << lhsJ_h[i] << " " << lhs_h[i] << endl;
	}
	posFile.close();

	return 0;
}

int ANCFSystem::writeToFile()
{
	char filename[100];
	sprintf(filename, "../posData/pos%d.dat", fileIndex);
	posFile.open(filename);
	p_h = p_d;
	double* posAll = CASTD1(p_h);
	double* pos;
	float3 posPart;
	double l;
	double r;
	posFile << elements.size() << ", " << particles.size() << ", " << "0" << "," << endl;
	for(int i=0;i<particles.size();i++)
	{
		r = particles[i].getRadius();
		posPart = getXYZPositionParticle(i);
		posFile << r << ", " << posPart.x << ", " << posPart.y << ", " << posPart.z << "," << endl;
	}
	for(int i=0;i<elements.size();i++)
	{
		l = elements[i].getLength_l();
		r = elements[i].getRadius();
		pos = &posAll[12*i];
		posFile << r << ", " << l;
		for(int i=0;i<12;i++) posFile << ", " << pos[i];
		posFile << ","<< endl;
	}
	posFile.close();
	fileIndex++;

	return 0;
}
