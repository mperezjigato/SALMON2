module noncollinear_module

  implicit none

  private
  public :: calc_dm_noncollinear
  public :: rot_dm_noncollinear
  public :: rot_vxc_noncollinear
  public :: op_xc_noncollinear
  public :: calc_magnetization
  public :: calc_magnetization_micro
  public :: calc_magnetization_decomposed
  public :: calc_spin_current
  public :: simple_mixing_so

  complex(8),allocatable :: den_mat(:,:,:,:,:)
  complex(8),allocatable :: vxc_mat(:,:,:,:,:)
  complex(8),allocatable :: old_mat(:,:,:)
  complex(8),parameter :: zero=(0.0d0,0.0d0), zi=(0.0d0,1.0d0)
  real(8),allocatable :: rot_ang(:,:,:,:)
  complex(8),allocatable :: dmat_old(:,:,:,:,:) ! for mixing of GS

contains

  subroutine calc_dm_noncollinear( psi, system, info, mg )
    use structures, only : s_dft_system, s_parallel_info, s_rgrid, s_orbital
    use communication, only: comm_summation
    implicit none
    type(s_orbital),intent(in) :: psi
    type(s_dft_system),intent(in) :: system
    type(s_parallel_info),intent(in) :: info
    type(s_rgrid),intent(in) :: mg
    integer :: io,ik,im,is,js,ix,iy,iz,m1,m2,m3,n1,n2,n3
    complex(8),allocatable :: ztmp(:,:,:),dmat_tmp(:,:,:,:,:)
    real(8) :: occ

    if ( .not.allocated(den_mat) ) then
       m1=mg%is(1); n1=mg%ie(1)
       m2=mg%is(2); n2=mg%ie(2)
       m3=mg%is(3); n3=mg%ie(3)
       allocate( den_mat(m1:n1,m2:n2,m3:n3,2,2) )
       den_mat=zero
    end if

    den_mat=zero

#ifdef USE_OPENACC
!$acc kernels
!#acc loop collapse(3) private(im,ik,io,occ,js,is,iz,iy,ix) reduction(+:den_mat)
#else
!$omp parallel do collapse(3) default(shared) private(im,ik,io,occ,js,is,iz,iy,ix) reduction(+:den_mat)
#endif
    do im=info%im_s,info%im_e
    do ik=info%ik_s,info%ik_e
    do io=info%io_s,info%io_e
       occ=system%rocc(io,ik,1)*system%wtk(ik)
       if ( abs(occ) < 1.0d-15 ) cycle
       do js=1,2
       do is=1,2
          do iz=mg%is(3),mg%ie(3)
          do iy=mg%is(2),mg%ie(2)
          do ix=mg%is(1),mg%ie(1)
             den_mat(ix,iy,iz,is,js) = den_mat(ix,iy,iz,is,js) + occ &
                  * psi%zwf(ix,iy,iz,is,io,ik,im) * conjg( psi%zwf(ix,iy,iz,js,io,ik,im) )
          end do
          end do
          end do
       end do !is
       end do !js
    end do !io
    end do !ik
    end do !im
#ifdef USE_OPENACC
!$acc end kernels
#endif

    ix=size(den_mat,1)
    iy=size(den_mat,2)
    iz=size(den_mat,3)
    allocate( dmat_tmp(ix,iy,iz,2,2) ); dmat_tmp=den_mat
    call comm_summation( dmat_tmp, den_mat, size(dmat_tmp), info%icomm_ko )
    deallocate( dmat_tmp )

    !m1=mg%is(1); n1=mg%ie(1)
    !m2=mg%is(2); n2=mg%ie(2)
    !m3=mg%is(3); n3=mg%ie(3)
    !allocate( ztmp(m1:n1,m2:n2,m3:n3) ); ztmp=zero
    !ztmp(:,:,:)=ztmp(:,:,:)+den_mat(:,:,:,1,1)+den_mat(:,:,:,2,2)
    !write(*,*) sum(real(ztmp))*system%hvol,sum(aimag(ztmp))*system%hvol
    !write(*,*) minval(real(ztmp)),minval(aimag(ztmp))
    !write(*,*) maxval(real(ztmp)),maxval(aimag(ztmp))
    !deallocate(ztmp)
 
  end subroutine calc_dm_noncollinear


  subroutine rot_dm_noncollinear( rho, system, mg )
    use structures, only : s_dft_system, s_rgrid, s_scalar
    use communication, only : comm_summation
    implicit none
    type(s_dft_system),intent(in) :: system
    type(s_rgrid),intent(in) :: mg
    type(s_scalar),intent(inout) :: rho(system%nspin)
    real(8) :: phi,theta,tmp,tmp1
    integer :: a,b,m1,m2,m3,n1,n2,n3,ix,iy,iz

    if ( .not.allocated(rot_ang) ) then
       m1=mg%is(1) ; n1=mg%ie(1)
       m2=mg%is(2) ; n2=mg%ie(2)
       m3=mg%is(3) ; n3=mg%ie(3)
       allocate( rot_ang(m1:n1,m2:n2,m3:n3,2) ) ; rot_ang=0.0d0
    end if

    rot_ang=0.0d0

    a=1
    b=2
#ifdef USE_OPENACC
!$acc kernels
!#acc loop collapse(2) private(iz,iy,ix,phi,theta)
#else
!$omp parallel do collapse(2) default(shared) private(iz,iy,ix,phi,theta)
#endif
    do iz=mg%is(3),mg%ie(3)
    do iy=mg%is(2),mg%ie(2)
    do ix=mg%is(1),mg%ie(1)

       phi = -atan( aimag(den_mat(ix,iy,iz,a,b))/dble(den_mat(ix,iy,iz,a,b)) )
       theta = atan( 2.0d0*( dble(den_mat(ix,iy,iz,a,b))*cos(phi) &
            -aimag(den_mat(ix,iy,iz,a,b))*sin(phi) ) &
            /dble( den_mat(ix,iy,iz,a,a)-den_mat(ix,iy,iz,b,b) ) )

       rho(1)%f(ix,iy,iz) = 0.5d0*dble( den_mat(ix,iy,iz,a,a)+den_mat(ix,iy,iz,b,b) ) &
            + 0.5d0*dble( den_mat(ix,iy,iz,a,a)-den_mat(ix,iy,iz,b,b) )*cos(theta) &
            + (  dble(den_mat(ix,iy,iz,a,b))*cos(phi) &
            -aimag(den_mat(ix,iy,iz,a,b))*sin(phi) )*sin(theta)

       rho(2)%f(ix,iy,iz) = 0.5d0*dble( den_mat(ix,iy,iz,a,a)+den_mat(ix,iy,iz,b,b) ) &
            - 0.5d0*dble( den_mat(ix,iy,iz,a,a)-den_mat(ix,iy,iz,b,b) )*cos(theta) &
            - (  dble(den_mat(ix,iy,iz,a,b))*cos(phi) &
            -aimag(den_mat(ix,iy,iz,a,b))*sin(phi) )*sin(theta)

       rot_ang(ix,iy,iz,1) = phi
       rot_ang(ix,iy,iz,2) = theta

    end do !ix
    end do !iy
    end do !iz
#ifdef USE_OPENACC
!$acc end kernels
#endif

    !write(*,*) "size(rho%f)",(size(rho(1)%f,ix),ix=1,3)
    !tmp=sum(rho(1)%f+rho(2)%f)*system%hvol
    !call comm_summation( tmp, tmp1, MPI_COMM_WORLD )
    !write(*,*) "sum(rho)@rot_dm_noncollinear",tmp1
    !write(*,*) minval(rho(1)%f),minval(rho(2)%f)
    !write(*,*) maxval(rho(1)%f),maxval(rho(2)%f)

  end subroutine rot_dm_noncollinear


  subroutine rot_vxc_noncollinear( Vxc, system, mg )
    use structures, only : s_dft_system, s_rgrid, s_scalar
    implicit none
    type(s_dft_system),intent(in) :: system
    type(s_rgrid),intent(in) :: mg
    type(s_scalar),intent(inout) :: Vxc(system%nspin)
    real(8) :: phi,theta,vxc_0,vxc_1
    integer :: ix,iy,iz,m1,m2,m3,n1,n2,n3

    if ( .not.allocated(vxc_mat) ) then
       m1=mg%is(1); n1=mg%ie(1)
       m2=mg%is(2); n2=mg%ie(2)
       m3=mg%is(3); n3=mg%ie(3)
       allocate( vxc_mat(m1:n1,m2:n2,m3:n3,2,2) )
    end if
    vxc_mat=zero

#ifdef USE_OPENACC
!$acc kernels
!#acc loop collapse(2) private(iz,iy,ix,phi,theta,vxc_0,vxc_1)
#else
!$omp parallel do collapse(2) default(shared) private(iz,iy,ix,phi,theta,vxc_0,vxc_1)
#endif
    do iz=mg%is(3),mg%ie(3)
    do iy=mg%is(2),mg%ie(2)
    do ix=mg%is(1),mg%ie(1)

       phi = rot_ang(ix,iy,iz,1)
       theta = rot_ang(ix,iy,iz,2)

       vxc_0 = 0.5d0*( Vxc(1)%f(ix,iy,iz) + Vxc(2)%f(ix,iy,iz) )
       vxc_1 = 0.5d0*( Vxc(1)%f(ix,iy,iz) - Vxc(2)%f(ix,iy,iz) )

       vxc_mat(ix,iy,iz,1,1) = vxc_0 + vxc_1*cos(theta)
       vxc_mat(ix,iy,iz,2,1) = vxc_1*dcmplx( cos(phi), sin(phi) )*sin(theta)
       vxc_mat(ix,iy,iz,1,2) = vxc_1*dcmplx( cos(phi),-sin(phi) )*sin(theta)
       vxc_mat(ix,iy,iz,2,2) = vxc_0 - vxc_1*cos(theta)

    end do !ix
    end do !iy
    end do !iz
#ifdef USE_OPENACC
!$acc end kernels
#endif

    Vxc(1)%f=0.0d0
    Vxc(2)%f=0.0d0

  end subroutine rot_vxc_noncollinear


  subroutine op_xc_noncollinear( tpsi, hpsi, info, mg )
    use structures, only : s_orbital, s_rgrid, s_parallel_info
    implicit none
    type(s_orbital),intent(in) :: tpsi
    type(s_orbital),intent(inout) :: hpsi
    type(s_rgrid),intent(in) :: mg
    type(s_parallel_info),intent(in) :: info
    integer :: ix,iy,iz,im,ik,io
    if ( .not.allocated(vxc_mat) ) return
#ifdef USE_OPENACC
!$acc kernels
!#acc loop collapse(5) private(im,ik,io,iz,iy,ix)
#else
!$omp parallel do collapse(5) default(shared) private(im,ik,io,iz,iy,ix)
#endif
    do im=info%im_s,info%im_e
    do ik=info%ik_s,info%ik_e
    do io=info%io_s,info%io_e
       do iz=mg%is(3),mg%ie(3)
       do iy=mg%is(2),mg%ie(2)
       do ix=mg%is(1),mg%ie(1)
          hpsi%zwf(ix,iy,iz,1,io,ik,im) = hpsi%zwf(ix,iy,iz,1,io,ik,im) &
               + vxc_mat(ix,iy,iz,1,1)*tpsi%zwf(ix,iy,iz,1,io,ik,im) &
               + vxc_mat(ix,iy,iz,1,2)*tpsi%zwf(ix,iy,iz,2,io,ik,im)
          hpsi%zwf(ix,iy,iz,2,io,ik,im) = hpsi%zwf(ix,iy,iz,2,io,ik,im) &
               + vxc_mat(ix,iy,iz,2,1)*tpsi%zwf(ix,iy,iz,1,io,ik,im) &
               + vxc_mat(ix,iy,iz,2,2)*tpsi%zwf(ix,iy,iz,2,io,ik,im)
       end do
       end do
       end do
    end do
    end do
    end do
#ifdef USE_OPENACC
!$acc end kernels
#endif
  end subroutine op_xc_noncollinear

! for GS calculation
  subroutine simple_mixing_so(mg,system,c1,c2,rho_s,mixing)
    use structures
    implicit none
    type(s_rgrid)     ,intent(in) :: mg
    type(s_dft_system),intent(in) :: system
    real(8)           ,intent(in) :: c1,c2
    type(s_scalar)                :: rho_s(system%nspin)
    type(s_mixing)                :: mixing
    !
    integer ix,iy,iz,m1,m2,m3,n1,n2,n3
    
    if ( .not.allocated(dmat_old) ) then
       m1=mg%is(1); n1=mg%ie(1)
       m2=mg%is(2); n2=mg%ie(2)
       m3=mg%is(3); n3=mg%ie(3)
       allocate( dmat_old(m1:n1,m2:n2,m3:n3,2,2) )
       !$omp workshare
       dmat_old = den_mat
       !$omp end workshare
    end if
  
  ! rho = c1*rho + c2*matmul( psi**2, occ )

    !$omp workshare
    den_mat = c1*dmat_old + c2*den_mat
    dmat_old = den_mat
    !$omp end workshare

  ! calculate the rotation matrix
  
    call rot_dm_noncollinear( rho_s, system, mg )
    
  ! update the density from the diagonal components
  
    !$omp workshare
    rho_s(1)%f = dble(den_mat(:,:,:,1,1))
    rho_s(2)%f = dble(den_mat(:,:,:,2,2))
    !$omp end workshare
  
  end subroutine simple_mixing_so


  subroutine calc_magnetization(system,mg,info,m)
    use structures
    use communication, only: comm_summation
    implicit none
    type(s_dft_system),   intent(in) :: system
    type(s_rgrid),        intent(in) :: mg
    type(s_parallel_info),intent(in) :: info
    real(8)                          :: m(3)
    !
    integer :: ix,iy,iz
    real(8)    :: m_tmp(3)
    complex(8) :: zmat(2,2)
    
    zmat = zero
#ifdef USE_OPENACC
!$acc kernels
!#acc loop collapse(2) private(ix,iy,iz) reduction(+:zmat)
#else
!$omp parallel do collapse(2) private(ix,iy,iz) reduction(+:zmat)
#endif
    do iz=mg%is(3),mg%ie(3)
    do iy=mg%is(2),mg%ie(2)
    do ix=mg%is(1),mg%ie(1)
      zmat(1:2,1:2) = zmat(1:2,1:2) + den_mat(ix,iy,iz,1:2,1:2) * system%hvol
    end do
    end do
    end do
#ifdef USE_OPENACC
!$acc end kernels
#endif
    
    m_tmp(1) = 0.5d0* dble( zmat(1,2) + zmat(2,1) )
    m_tmp(2) = 0.5d0* dble( -zi* zmat(1,2) + zi* zmat(2,1) )
    m_tmp(3) = 0.5d0* dble( zmat(1,1) - zmat(2,2) )
    call comm_summation( m_tmp, m, 3, info%icomm_r )
    return
  end subroutine calc_magnetization


  subroutine calc_magnetization_micro(mg,m)
    use structures
    implicit none
    type(s_rgrid), intent(in) :: mg
    real(8)                   :: m(mg%is(1):mg%ie(1),mg%is(2):mg%ie(2),mg%is(3):mg%ie(3),1:3)
    !
    m(:,:,:,1) = 0.5d0* dble( den_mat(:,:,:,1,2) + den_mat(:,:,:,2,1) )
    m(:,:,:,2) = 0.5d0* dble( -zi* den_mat(:,:,:,1,2) + zi* den_mat(:,:,:,2,1) )
    m(:,:,:,3) = 0.5d0* dble( den_mat(:,:,:,1,1) - den_mat(:,:,:,2,2) )
    return
  end subroutine calc_magnetization_micro
  
  
  subroutine calc_magnetization_decomposed(system,mg,info,psi,mag_orb)
    use structures
    use communication, only: comm_summation
    implicit none
    type(s_dft_system),   intent(in) :: system
    type(s_rgrid),        intent(in) :: mg
    type(s_parallel_info),intent(in) :: info
    type(s_orbital),      intent(in) :: psi
    real(8)                          :: mag_orb(3,system%no,system%nk)
    !
    integer,parameter :: im = 1
    integer :: ix,iy,iz,ik,io,is,js
    real(8)    :: m_tmp(3,system%no,system%nk)
    complex(8) :: zmat(2,2)
    
    m_tmp = zero
#ifdef USE_OPENACC
!$acc kernels
!#acc loop collapse(2) private(ik,io,is,js,ix,iy,iz,zmat)
#else
!$omp parallel do collapse(2) private(ik,io,is,js,ix,iy,iz,zmat)
#endif
    do ik=info%ik_s,info%ik_e
    do io=info%io_s,info%io_e
      zmat = zero
      do js=1,2
      do is=1,2
        do iz=mg%is(3),mg%ie(3)
        do iy=mg%is(2),mg%ie(2)
        do ix=mg%is(1),mg%ie(1)
          zmat(is,js) = zmat(is,js) + psi%zwf(ix,iy,iz,is,io,ik,im) * conjg( psi%zwf(ix,iy,iz,js,io,ik,im) )
        end do
        end do
        end do
      end do !is
      end do !js
      zmat = zmat * system%hvol
      m_tmp(1,io,ik) = 0.5d0* dble( zmat(1,2) + zmat(2,1) )
      m_tmp(2,io,ik) = 0.5d0* dble( -zi* zmat(1,2) + zi* zmat(2,1) )
      m_tmp(3,io,ik) = 0.5d0* dble( zmat(1,1) - zmat(2,2) )
    end do !io
    end do !ik
#ifdef USE_OPENACC
!$acc end kernels
#endif
    
    call comm_summation( m_tmp, mag_orb, 3*system%no*system%nk, info%icomm_rko )
    return
  end subroutine calc_magnetization_decomposed

  
! spin current density
! cf. N. Tancogne-Dejean et al, npj Computational Materials 8, 145 (2022).
  subroutine calc_spin_current(system,mg,stencil,info,psi,ppg,spin_curr_micro,spin_curr_band)
    use structures
    use communication, only: comm_summation
    use pseudo_pt_current_so, only: calc_spin_current_nonlocal
    implicit none
    type(s_dft_system)   ,intent(in) :: system
    type(s_rgrid)        ,intent(in) :: mg
    type(s_stencil)      ,intent(in) :: stencil
    type(s_parallel_info),intent(in) :: info
    type(s_orbital)      ,intent(in) :: psi
    type(s_pp_grid)      ,intent(in) :: ppg
    real(8)                          :: spin_curr_micro(3,0:3, &
                                        & mg%is(1):mg%ie(1),mg%is(2):mg%ie(2),mg%is(3):mg%ie(3))
    real(8)                          :: spin_curr_band(3,0:3,system%no,system%nk)
    !
    integer,parameter :: im = 1
    integer :: ispin,ik,io,ix,iy,iz,i
    real(8),dimension(3,0:3) :: jspin_l,jspin_nl
    real(8) :: kAc(3)
    complex(8) :: p(2),g(3,2),sig(3,0:3)
    real(8) :: wrk_micro(3,0:3,mg%is(1):mg%ie(1),mg%is(2):mg%ie(2),mg%is(3):mg%ie(3))
    real(8) :: wrk_band(3,0:3,system%no,system%nk)
    complex(8) :: gtpsi(3,mg%is_array(1):mg%ie_array(1) &
                       & ,mg%is_array(2):mg%ie_array(2) &
                       & ,mg%is_array(3):mg%ie_array(3),2)

    if(info%if_divide_rspace) then
    !!!! future work
      stop("calc_spin_current_density: r-space parallelization for spin-noncollinear systems is not implemented")
    end if

    wrk_micro = 0d0
    wrk_band = 0d0
    do ik=info%ik_s,info%ik_e
    do io=info%io_s,info%io_e
      kAc(1:3) = system%vec_k(1:3,ik) + system%vec_Ac(1:3)
 
      ! gtpsi = (nabla) psi
      do ispin=1,2
        call calc_gradient_psi(psi%zwf(:,:,:,ispin,io,ik,im),gtpsi(:,:,:,:,ispin) &
        &    ,mg%is_array,mg%ie_array,mg%is,mg%ie &
        &    ,mg%idx,mg%idy,mg%idz,stencil%coef_nab,system%rmatrix_B)
      end do
      
      jspin_l = 0d0
      !$omp parallel do collapse(2) private(iz,iy,ix,p,g,sig) reduction(+:jspin_l)
      do iz=mg%is(3),mg%ie(3)
      do iy=mg%is(2),mg%ie(2)
      do ix=mg%is(1),mg%ie(1)
        p(:) = psi%zwf(ix,iy,iz,:,io,ik,im)
        g(:,1) = - zi* gtpsi(:,ix,iy,iz,1) + kAc(:) * p(1)
        g(:,2) = - zi* gtpsi(:,ix,iy,iz,2) + kAc(:) * p(2)

        sig(:,0) = conjg(p(1)) * g(:,1) + conjg(p(2)) * g(:,2)
        sig(:,1) = conjg(p(1)) * g(:,2) + conjg(p(2)) * g(:,1)
        sig(:,2) = -zi* ( conjg(p(1)) * g(:,2) - conjg(p(2)) * g(:,1) )
        sig(:,3) = conjg(p(1)) * g(:,1) - conjg(p(2)) * g(:,2)
        
        wrk_micro(:,:,ix,iy,iz) = wrk_micro(:,:,ix,iy,iz) &
        & + dble(sig) * system%rocc(io,ik,1)*system%wtk(ik)
        jspin_l = jspin_l + dble(sig)
      end do
      end do
      end do
      
      call calc_spin_current_nonlocal(jspin_nl,psi%zwf(:,:,:,:,io,ik,im),ppg,mg%is_array,mg%ie_array,ik )
      wrk_band(:,:,io,ik) = ( jspin_l + jspin_nl ) / dble(system%ngrid)
      
    end do ! io
    end do ! ik
    
    call comm_summation(wrk_micro,spin_curr_micro,3*4*mg%num(1)*mg%num(2)*mg%num(3),info%icomm_ko)
    call comm_summation(wrk_band,spin_curr_band,3*4*system%no*system%nk,info%icomm_rko)
    
    return
  end subroutine calc_spin_current

end module noncollinear_module
