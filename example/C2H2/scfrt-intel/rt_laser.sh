export OMP_NUM_THREADS=24
date > output_rt_laser
mpiexec -np 1 ../../../gceed < input_rt_laser >> output_rt_laser
date >> output_rt_laser
