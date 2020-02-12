!
!  Copyright 2019 SALMON developers
!
!  Licensed under the Apache License, Version 2.0 (the "License");
!  you may not use this file except in compliance with the License.
!  You may obtain a copy of the License at
!
!      http://www.apache.org/licenses/LICENSE-2.0
!
!  Unless required by applicable law or agreed to in writing, software
!  distributed under the License is distributed on an "AS IS" BASIS,
!  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
!  See the License for the specific language governing permissions and
!  limitations under the License.
!
module structure_opt_sub
  implicit none
  ! Global variables like below is not allowed by our policy
  ! These should be moved (do it later...)
  real(8),allocatable :: a_dRion(:), dFion(:)
  real(8),allocatable :: Hess_mat(:,:), Hess_mat_last(:,:)
contains

  !==============================================================initilize
  subroutine structure_opt_ini(natom)
    use parallelization, only: nproc_id_global
    use communication, only: comm_is_root
    implicit none
    integer,intent(in) :: natom

    allocate(a_dRion(3*natom),dFion(3*natom))
    allocate(Hess_mat(3*natom,3*natom),Hess_mat_last(3*natom,3*natom))

    a_dRion(:)=0d0
    dFion(:)  =0d0
    Hess_mat(:,:)     =0d0
    Hess_mat_last(:,:)=0d0
    if(comm_is_root(nproc_id_global))then
      write(*,*) "===== Grand State Optimization Start ====="
      write(*,*) "       (Quasi-Newton method using Force only)       "
    end if

  end subroutine structure_opt_ini

  !======================================================convergence check
  subroutine structure_opt_check(natom,iopt,flag_opt_conv,Force)
    use structures
    use salmon_global, only: convrg_opt_fmax,unit_system,flag_opt_atom
    use inputoutput, only: au_length_aa, au_energy_ev
    use parallelization, only: nproc_id_global,nproc_group_global
    use communication, only: comm_is_root,comm_bcast
    implicit none
    integer,intent(in) :: natom,iopt
    real(8),intent(in) :: Force(3,natom)
    logical,intent(inout) :: flag_opt_conv
    integer :: iatom,iatom_count
    real(8) :: fabs,fmax,fave

    fmax =0d0
    fave =0d0
    iatom_count=0
    do iatom=1,natom
      if(flag_opt_atom(iatom)=='y') then
        iatom_count = iatom_count+1
        fabs = sum(Force(:,iatom)**2d0)
        fave = fave + fabs
        if(fabs>=fmax) fmax = fabs
      end if
    enddo

    select case(unit_system)
    case('au','a.u.')
      fmax = sqrt(fmax)
      fave = sqrt(fave/iatom_count)
    case('A_eV_fs')
      fmax = sqrt(fmax)*au_energy_ev/au_length_aa
      fave = sqrt(fave/iatom_count)*au_energy_ev/au_length_aa
    end select

    if(comm_is_root(nproc_id_global))then
      write(*,*) " Max-force=",fmax, "  Mean-force=",fave
      write(*,*) "==================================================="
      write(*,*) "Quasi-Newton Optimization Step = ", iopt
      if(fmax<=convrg_opt_fmax) flag_opt_conv=.true.
    end if
    call comm_bcast(flag_opt_conv,nproc_group_global)

  end subroutine structure_opt_check

  !===========================================================optimization
  subroutine structure_opt(natom,iopt,system)
    use structures, only: s_dft_system
    use salmon_global, only: flag_opt_atom
    use communication, only: comm_bcast
    implicit none
    type(s_dft_system),intent(inout) :: system
    integer,intent(in) :: natom,iopt
    !theta_opt=0.0d0:DFP,theta_opt=1.0d0:BFGS in Quasi_Newton method
    real(8), parameter :: alpha=1.0d0,theta_opt=1.0d0
    integer :: ii,ij,jj,icount,iatom, NA3,ixyz
    real(8) :: const1,const2,rtmp
    real(8) :: dRion(3,natom)
    real(8) :: force_1d(3*natom),dRion_1d(3*natom),optmat_1d(3*natom)
    real(8) :: optmat1_2d(3*natom,3*natom),optmat2_2d(3*natom,3*natom),optmat3_2d(3*natom,3*natom)

    NA3 = 3*natom

    icount=1
    do iatom=1,natom
    do ixyz=1,3
       force_1d(icount) = system%Force(ixyz,iatom)
       icount = icount+1
    end do
    end do

    if(iopt==1)then
      !update Hess_mat
      do ii=1,NA3
      do ij=1,NA3
         if(ii==ij)then
            Hess_mat(ii,ij) = 1d0
         else
            Hess_mat(ii,ij) = 0d0
         end if
         Hess_mat_last(ii,ij) = Hess_mat(ii,ij)
      end do
      end do
    else
      !update dFion
      dFion=-(force_1d-dFion)
      !prepare const and matrix
      call dgemm('n','n',1,1,NA3,1.0d0,a_dRion,1,dFion,NA3,0d0,const1,1)
      call dgemm('n','n',NA3,1,NA3,1d0,Hess_mat,NA3,dFion,NA3,0d0,optmat_1d,NA3)
      call dgemm('n','n',1,1,NA3,1d0,dFion,1,optmat_1d,NA3,0d0,const2,1)
      call dgemm('n','n',NA3,NA3,1,1d0,a_dRion,NA3,a_dRion,1,0d0,optmat1_2d,NA3)
      !update Hess_mat
      rtmp = (const1+theta_opt*const2)/(const1**2d0)
      !$omp parallel do collapse(2) private(ii,jj)
      do ii=1,NA3
      do jj=1,NA3
         Hess_mat(ii,jj) = Hess_mat_last(ii,jj) + rtmp * optmat1_2d(ii,jj)
      enddo
      enddo
      !$omp end parallel do
      if(theta_opt==0.0d0)then
        !theta_opt=0.0d0:DFP
        call dgemm('n','n',NA3,NA3,1,1d0,optmat_1d,NA3,optmat_1d,1,0d0,optmat2_2d,NA3)
        !$omp parallel do collapse(2) private(ii,jj)
        do ii=1,NA3
        do jj=1,NA3
           Hess_mat(ii,jj) = Hess_mat(ii,jj)-(1d0/const2)*optmat2_2d(ii,jj)
        enddo
        enddo
        !$omp end parallel do
      elseif(theta_opt==1.0d0)then
        !theta_opt=1.0d0:BFGS
        call dgemm('n','n',NA3,NA3,1,1d0,optmat_1d,NA3,a_dRion,1,0d0,optmat2_2d,NA3)
        call dgemm('n','n',NA3,NA3,1,1d0,a_dRion,NA3,optmat_1d,1,0d0,optmat3_2d,NA3)
        rtmp = theta_opt/const1
        !$omp parallel do collapse(2) private(ii,jj)
        do ii=1,NA3
        do jj=1,NA3
           Hess_mat(ii,jj) = Hess_mat(ii,jj)- rtmp *(optmat2_2d(ii,jj)+optmat3_2d(ii,jj))
        enddo
        enddo
        !$omp end parallel do
      endif
      !update Hess_mat_last
      !$omp parallel do collapse(2) private(ii,jj)
      do ii=1,NA3
      do jj=1,NA3
         Hess_mat_last(ii,jj) = Hess_mat(ii,jj)
      enddo
      enddo
      !$omp end parallel do
    end if

    !update dRion_1d and dRion
    dRion_1d(:) = 0d0
    call dgemm('n','n',NA3,1,NA3,1d0,Hess_mat,NA3,force_1d,NA3,0d0,dRion_1d,NA3)
    !$omp parallel do collapse(2) private(iatom,ixyz)
    do iatom=1,natom
    do ixyz=1,3
       dRion(ixyz,iatom) = dRion_1d(ixyz+3*(iatom-1))       
!      dRion(1:3,iatom) = dRion_1d((1+3*(iatom-1)):(3+3*(iatom-1)))
    end do
    end do
    !$omp end parallel do

    !update a_dRion,dFion
    !$omp parallel do private(ii)
    do ii=1,NA3
       a_dRion(ii) = alpha * dRion_1d(ii)
       dFion(ii)   = force_1d(ii)
    enddo
    !$omp end parallel do

    !update Rion
    !$omp parallel do private(iatom)
    do iatom=1,natom
       if(flag_opt_atom(iatom)=='y') &
          system%Rion(1:3,iatom) = system%Rion(1:3,iatom) +alpha*dRion(1:3,iatom)
    end do
    !$omp end parallel do

  end subroutine structure_opt

  !===============================================================finilize
  subroutine structure_opt_fin
    use parallelization, only: nproc_id_global
    use communication, only: comm_is_root
    implicit none
    deallocate(a_dRion,dFion)
    deallocate(Hess_mat,Hess_mat_last)
    if(comm_is_root(nproc_id_global)) write(*,*) "Optimization Converged"
  end subroutine structure_opt_fin

end module structure_opt_sub
