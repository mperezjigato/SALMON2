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
!-----------------------------------------------------------------------------------------
subroutine eh_calc(fs,fw)
  use salmon_global,   only: dt_em,pole_num_ld,obs_num_em,obs_samp_em,yn_obs_plane_em,&
                             base_directory,t1_t2,t1_start,&
                             E_amplitude1,tw1,omega1,phi_cep1,epdir_re1,epdir_im1,ae_shape1,&
                             E_amplitude2,tw2,omega2,phi_cep2,epdir_re2,epdir_im2,ae_shape2
  use inputoutput,     only: utime_from_au
  use parallelization, only: nproc_id_global,nproc_size_global,nproc_group_global
  use communication,   only: comm_is_root,comm_summation
  use structures,      only: s_fdtd_system
  use salmon_maxwell,  only: ls_fdtd_work
  use math_constants,  only: pi
  implicit none
  type(s_fdtd_system),intent(inout) :: fs
  type(ls_fdtd_work), intent(inout) :: fw
  integer                           :: iter,ii,ij,ix,iy,iz
  character(128)                    :: save_name
  
  !time-iteration
  do iter=fw%iter_sta,fw%iter_end
    !update iter_now
    fw%iter_now=iter
    if(comm_is_root(nproc_id_global))then
      write(*,*) fw%iter_now
    end if
    
    !update lorentz-drude
    if(fw%num_ld>0) then
      call eh_update_ld
    end if
    
    !update e
    call eh_fd(fw%iex_y_is,fw%iex_y_ie,      fs%ng%is,fs%ng%ie,fw%Nd,&
               fw%c1_ex_y,fw%c2_ex_y,fw%ex_y,fw%hz_x,fw%hz_y,      'e','y') !ex_y
    call eh_fd(fw%iex_z_is,fw%iex_z_ie,      fs%ng%is,fs%ng%ie,fw%Nd,&
               fw%c1_ex_z,fw%c2_ex_z,fw%ex_z,fw%hy_z,fw%hy_x,      'e','z') !ex_z
    call eh_fd(fw%iey_z_is,fw%iey_z_ie,      fs%ng%is,fs%ng%ie,fw%Nd,&
               fw%c1_ey_z,fw%c2_ey_z,fw%ey_z,fw%hx_y,fw%hx_z,      'e','z') !ey_z
    call eh_fd(fw%iey_x_is,fw%iey_x_ie,      fs%ng%is,fs%ng%ie,fw%Nd,&
               fw%c1_ey_x,fw%c2_ey_x,fw%ey_x,fw%hz_x,fw%hz_y,      'e','x') !ey_x
    call eh_fd(fw%iez_x_is,fw%iez_x_ie,      fs%ng%is,fs%ng%ie,fw%Nd,&
               fw%c1_ez_x,fw%c2_ez_x,fw%ez_x,fw%hy_z,fw%hy_x,      'e','x') !ez_x
    call eh_fd(fw%iez_y_is,fw%iez_y_ie,      fs%ng%is,fs%ng%ie,fw%Nd,&
               fw%c1_ez_y,fw%c2_ez_y,fw%ez_y,fw%hx_y,fw%hx_z,      'e','y') !ez_y
    if(fw%inc_num>0) then                                !add incident current source
      if(fw%inc_dist1/='none') call eh_add_inc(1,E_amplitude1,tw1,omega1,phi_cep1,&
                                                  epdir_re1,epdir_im1,ae_shape1,fw%inc_dist1)
      if(fw%inc_dist2/='none') call eh_add_inc(2,E_amplitude2,tw2,omega2,phi_cep2,&
                                                  epdir_re2,epdir_im2,ae_shape2,fw%inc_dist2)
    end if
    if(fw%num_ld>0) then
      call eh_add_curr(fw%rjx_sum_ld(:,:,:),fw%rjy_sum_ld(:,:,:),fw%rjz_sum_ld(:,:,:))
    end if
    call eh_sendrecv(fs,fw,'e')
    
    !calculate linear response
    if(ae_shape1=='impulse'.or.ae_shape2=='impulse') then
      call eh_calc_lr
    end if
    
    !store old h
    if( (obs_num_em>0).and.(mod(iter,obs_samp_em)==0) )then
!$omp parallel
!$omp do private(ix,iy,iz)
      do iz=(fs%ng%is_array(3)),(fs%ng%ie_array(3))
      do iy=(fs%ng%is_array(2)),(fs%ng%ie_array(2))
      do ix=(fs%ng%is_array(1)),(fs%ng%ie_array(1))
        fw%hx_s(ix,iy,iz)=fw%hx_y(ix,iy,iz)+fw%hx_z(ix,iy,iz)
        fw%hy_s(ix,iy,iz)=fw%hy_z(ix,iy,iz)+fw%hy_x(ix,iy,iz)
        fw%hz_s(ix,iy,iz)=fw%hz_x(ix,iy,iz)+fw%hz_y(ix,iy,iz)
      end do
      end do
      end do
!$omp end do
!$omp end parallel
    end if
    
    !update h
    call eh_fd(fw%ihx_y_is,fw%ihx_y_ie,      fs%ng%is,fs%ng%ie,fw%Nd,&
               fw%c1_hx_y,fw%c2_hx_y,fw%hx_y,fw%ez_x,fw%ez_y,      'h','y') !hx_y
    call eh_fd(fw%ihx_z_is,fw%ihx_z_ie,      fs%ng%is,fs%ng%ie,fw%Nd,&
               fw%c1_hx_z,fw%c2_hx_z,fw%hx_z,fw%ey_z,fw%ey_x,      'h','z') !hx_z
    call eh_fd(fw%ihy_z_is,fw%ihy_z_ie,      fs%ng%is,fs%ng%ie,fw%Nd,&
               fw%c1_hy_z,fw%c2_hy_z,fw%hy_z,fw%ex_y,fw%ex_z,      'h','z') !hy_z
    call eh_fd(fw%ihy_x_is,fw%ihy_x_ie,      fs%ng%is,fs%ng%ie,fw%Nd,&
               fw%c1_hy_x,fw%c2_hy_x,fw%hy_x,fw%ez_x,fw%ez_y,      'h','x') !hy_x
    call eh_fd(fw%ihz_x_is,fw%ihz_x_ie,      fs%ng%is,fs%ng%ie,fw%Nd,&
               fw%c1_hz_x,fw%c2_hz_x,fw%hz_x,fw%ey_z,fw%ey_x,      'h','x') !hz_x
    call eh_fd(fw%ihz_y_is,fw%ihz_y_ie,      fs%ng%is,fs%ng%ie,fw%Nd,&
               fw%c1_hz_y,fw%c2_hz_y,fw%hz_y,fw%ex_y,fw%ex_z,      'h','y') !hz_y
    call eh_sendrecv(fs,fw,'h')
    
    !observation
    if( (obs_num_em>0).and.(mod(iter,obs_samp_em)==0) )then
      !prepare e and h for save
!$omp parallel
!$omp do private(ix,iy,iz)
      do iz=(fs%ng%is_array(3)),(fs%ng%ie_array(3))
      do iy=(fs%ng%is_array(2)),(fs%ng%ie_array(2))
      do ix=(fs%ng%is_array(1)),(fs%ng%ie_array(1))
        fw%ex_s(ix,iy,iz)=fw%ex_y(ix,iy,iz)+fw%ex_z(ix,iy,iz)
        fw%ey_s(ix,iy,iz)=fw%ey_z(ix,iy,iz)+fw%ey_x(ix,iy,iz)
        fw%ez_s(ix,iy,iz)=fw%ez_x(ix,iy,iz)+fw%ez_y(ix,iy,iz)
        fw%hx_s(ix,iy,iz)=( fw%hx_s(ix,iy,iz)+(fw%hx_y(ix,iy,iz)+fw%hx_z(ix,iy,iz)) )/2.0d0
        fw%hy_s(ix,iy,iz)=( fw%hy_s(ix,iy,iz)+(fw%hy_z(ix,iy,iz)+fw%hy_x(ix,iy,iz)) )/2.0d0
        fw%hz_s(ix,iy,iz)=( fw%hz_s(ix,iy,iz)+(fw%hz_x(ix,iy,iz)+fw%hz_y(ix,iy,iz)) )/2.0d0
      end do
      end do
      end do
!$omp end do
!$omp end parallel
      call eh_sendrecv(fs,fw,'s')
      
      !save data
      do ii=1,obs_num_em
        !point
        if(fw%iobs_po_pe(ii)==1) then
          write(save_name,*) ii
          save_name=trim(adjustl(base_directory))//'/obs'//trim(adjustl(save_name))//'_at_point_rt.data'
          open(fw%ifn,file=save_name,status='old',position='append')
          write(fw%ifn,"(F16.8,99(1X,E23.15E3))",advance='no')                                          &
                dble(iter)*dt_em*utime_from_au,                                                         &
                fw%ex_s(fw%iobs_po_id(ii,1),fw%iobs_po_id(ii,2),fw%iobs_po_id(ii,3))*fw%uVperm_from_au, &
                fw%ey_s(fw%iobs_po_id(ii,1),fw%iobs_po_id(ii,2),fw%iobs_po_id(ii,3))*fw%uVperm_from_au, &
                fw%ez_s(fw%iobs_po_id(ii,1),fw%iobs_po_id(ii,2),fw%iobs_po_id(ii,3))*fw%uVperm_from_au, &
                fw%hx_s(fw%iobs_po_id(ii,1),fw%iobs_po_id(ii,2),fw%iobs_po_id(ii,3))*fw%uAperm_from_au, &
                fw%hy_s(fw%iobs_po_id(ii,1),fw%iobs_po_id(ii,2),fw%iobs_po_id(ii,3))*fw%uAperm_from_au, &
                fw%hz_s(fw%iobs_po_id(ii,1),fw%iobs_po_id(ii,2),fw%iobs_po_id(ii,3))*fw%uAperm_from_au
          close(fw%ifn)
        end if
        
        !plane
        if(yn_obs_plane_em(ii)=='y') then
          call eh_save_plane(fw%iobs_po_id(ii,:),fw%iobs_pl_pe(ii,:),fw%uVperm_from_au,&
                             fs%ng%is,fs%ng%ie,fs%lg%is,fs%lg%ie,fw%Nd,fw%ifn,ii,iter,fw%ex_s,'ex')
          call eh_save_plane(fw%iobs_po_id(ii,:),fw%iobs_pl_pe(ii,:),fw%uVperm_from_au,&
                             fs%ng%is,fs%ng%ie,fs%lg%is,fs%lg%ie,fw%Nd,fw%ifn,ii,iter,fw%ey_s,'ey')
          call eh_save_plane(fw%iobs_po_id(ii,:),fw%iobs_pl_pe(ii,:),fw%uVperm_from_au,&
                             fs%ng%is,fs%ng%ie,fs%lg%is,fs%lg%ie,fw%Nd,fw%ifn,ii,iter,fw%ez_s,'ez')
          call eh_save_plane(fw%iobs_po_id(ii,:),fw%iobs_pl_pe(ii,:),fw%uAperm_from_au,&
                             fs%ng%is,fs%ng%ie,fs%lg%is,fs%lg%ie,fw%Nd,fw%ifn,ii,iter,fw%hx_s,'hx')
          call eh_save_plane(fw%iobs_po_id(ii,:),fw%iobs_pl_pe(ii,:),fw%uAperm_from_au,&
                             fs%ng%is,fs%ng%ie,fs%lg%is,fs%lg%ie,fw%Nd,fw%ifn,ii,iter,fw%hy_s,'hy')
          call eh_save_plane(fw%iobs_po_id(ii,:),fw%iobs_pl_pe(ii,:),fw%uAperm_from_au,&
                             fs%ng%is,fs%ng%ie,fs%lg%is,fs%lg%ie,fw%Nd,fw%ifn,ii,iter,fw%hz_s,'hz')
        end if
      end do
      
      !check maximum
      call eh_update_max
    end if
    
  end do
  
contains
  
  !=========================================================================================
  != update lorentz-drude ==================================================================
  subroutine eh_update_ld
    implicit none
    
    !initialize
!$omp parallel
!$omp do private(ix,iy,iz)
    do iz=fs%ng%is(3),fs%ng%ie(3)
    do iy=fs%ng%is(2),fs%ng%ie(2)
    do ix=fs%ng%is(1),fs%ng%ie(1)
      fw%rjx_sum_ld(ix,iy,iz)=0.0d0; fw%rjy_sum_ld(ix,iy,iz)=0.0d0; fw%rjz_sum_ld(ix,iy,iz)=0.0d0;
      fw%px_sum_ld(ix,iy,iz) =0.0d0; fw%py_sum_ld(ix,iy,iz) =0.0d0; fw%pz_sum_ld(ix,iy,iz) =0.0d0;
    end do
    end do
    end do
!$omp end do
!$omp end parallel
    
    !update ld polarization vector
    do ii=1,fw%num_ld
    do ij=1,pole_num_ld(fw%media_ld(ii))
!$omp parallel
!$omp do private(ix,iy,iz)
      do iz=fs%ng%is(3),fs%ng%ie(3)
      do iy=fs%ng%is(2),fs%ng%ie(2)
      do ix=fs%ng%is(1),fs%ng%ie(1)
        fw%px_ld(ix,iy,iz,ij,ii)=fw%px_ld(ix,iy,iz,ij,ii)+dt_em*fw%rjx_ld(ix,iy,iz,ij,ii)
        fw%py_ld(ix,iy,iz,ij,ii)=fw%py_ld(ix,iy,iz,ij,ii)+dt_em*fw%rjy_ld(ix,iy,iz,ij,ii)
        fw%pz_ld(ix,iy,iz,ij,ii)=fw%pz_ld(ix,iy,iz,ij,ii)+dt_em*fw%rjz_ld(ix,iy,iz,ij,ii)
        fw%px_sum_ld(ix,iy,iz)=fw%px_sum_ld(ix,iy,iz)+fw%px_ld(ix,iy,iz,ij,ii)
        fw%py_sum_ld(ix,iy,iz)=fw%py_sum_ld(ix,iy,iz)+fw%py_ld(ix,iy,iz,ij,ii)
        fw%pz_sum_ld(ix,iy,iz)=fw%pz_sum_ld(ix,iy,iz)+fw%pz_ld(ix,iy,iz,ij,ii)
      end do
      end do
      end do
!$omp end do
!$omp end parallel
    end do
    end do
    
    !update ld polarization  current
    do ii=1,fw%num_ld
    do ij=1,pole_num_ld(fw%media_ld(ii))
!$omp parallel
!$omp do private(ix,iy,iz)
      do iz=fs%ng%is(3),fs%ng%ie(3)
      do iy=fs%ng%is(2),fs%ng%ie(2)
      do ix=fs%ng%is(1),fs%ng%ie(1)
        fw%rjx_ld(ix,iy,iz,ij,ii)= fw%c1_j_ld(ij,ii)*fw%rjx_ld(ix,iy,iz,ij,ii) &
                                  +fw%c2_j_ld(ij,ii)*( fw%ex_y(ix,iy,iz)+fw%ex_z(ix,iy,iz) ) &
                                  *dble(fw%idx_ld(ix,iy,iz,ii)) &
                                  -fw%c3_j_ld(ij,ii)*fw%px_ld(ix,iy,iz,ij,ii)
        fw%rjy_ld(ix,iy,iz,ij,ii)= fw%c1_j_ld(ij,ii)*fw%rjy_ld(ix,iy,iz,ij,ii) &
                                  +fw%c2_j_ld(ij,ii)*( fw%ey_z(ix,iy,iz)+fw%ey_x(ix,iy,iz) ) &
                                  *dble(fw%idy_ld(ix,iy,iz,ii)) &
                                  -fw%c3_j_ld(ij,ii)*fw%py_ld(ix,iy,iz,ij,ii)
        fw%rjz_ld(ix,iy,iz,ij,ii)= fw%c1_j_ld(ij,ii)*fw%rjz_ld(ix,iy,iz,ij,ii) &
                                  +fw%c2_j_ld(ij,ii)*( fw%ez_x(ix,iy,iz)+fw%ez_y(ix,iy,iz) ) &
                                  *dble(fw%idz_ld(ix,iy,iz,ii)) &
                                  -fw%c3_j_ld(ij,ii)*fw%pz_ld(ix,iy,iz,ij,ii)
        fw%rjx_sum_ld(ix,iy,iz)=fw%rjx_sum_ld(ix,iy,iz)+fw%rjx_ld(ix,iy,iz,ij,ii)
        fw%rjy_sum_ld(ix,iy,iz)=fw%rjy_sum_ld(ix,iy,iz)+fw%rjy_ld(ix,iy,iz,ij,ii)
        fw%rjz_sum_ld(ix,iy,iz)=fw%rjz_sum_ld(ix,iy,iz)+fw%rjz_ld(ix,iy,iz,ij,ii)
      end do
      end do
      end do
!$omp end do
!$omp end parallel
    end do
    end do
    
  end subroutine eh_update_ld
  
  !=========================================================================================
  != calculate linear response =============================================================
  subroutine eh_calc_lr
    use salmon_global, only: yn_periodic
    implicit none
    real(8) :: sum_lr_x,sum_lr_y,sum_lr_z
    real(8) :: sum_lr(3),sum_lr2(3)
    
    !update time
    fw%time_lr(fw%iter_lr)=dble(fw%iter_lr)*dt_em
    
    if(yn_periodic=='n') then
      !initialize polarization vector
!$omp parallel
!$omp do private(ix,iy,iz)
      do iz=fs%ng%is(3),fs%ng%ie(3)
      do iy=fs%ng%is(2),fs%ng%ie(2)
      do ix=fs%ng%is(1),fs%ng%ie(1)
        fw%px_lr(ix,iy,iz)=0.0d0; fw%py_lr(ix,iy,iz)=0.0d0; fw%pz_lr(ix,iy,iz)=0.0d0;
      end do
      end do
      end do
!$omp end do
!$omp end parallel
      
      !add all polarization vector
      if(fw%num_ld>0) then
!$omp parallel
!$omp do private(ix,iy,iz)
        do iz=fs%ng%is(3),fs%ng%ie(3)
        do iy=fs%ng%is(2),fs%ng%ie(2)
        do ix=fs%ng%is(1),fs%ng%ie(1)
          fw%px_lr(ix,iy,iz)=fw%px_lr(ix,iy,iz)+fw%px_sum_ld(ix,iy,iz);
          fw%py_lr(ix,iy,iz)=fw%py_lr(ix,iy,iz)+fw%py_sum_ld(ix,iy,iz);
          fw%pz_lr(ix,iy,iz)=fw%pz_lr(ix,iy,iz)+fw%pz_sum_ld(ix,iy,iz);
        end do
        end do
        end do
!$omp end do
!$omp end parallel
      end if
      
      !calculate dipolemoment
      sum_lr_x=0.0d0;  sum_lr_y=0.0d0;  sum_lr_z=0.0d0;
      sum_lr(:)=0.0d0; sum_lr2(:)=0.0d0;
!$omp parallel
!$omp do private(ix,iy,iz) reduction( + : sum_lr_x,sum_lr_y,sum_lr_z )
      do iz=fs%ng%is(3),fs%ng%ie(3)
      do iy=fs%ng%is(2),fs%ng%ie(2)
      do ix=fs%ng%is(1),fs%ng%ie(1)
        sum_lr_x=sum_lr_x+fw%px_lr(ix,iy,iz)
        sum_lr_y=sum_lr_y+fw%py_lr(ix,iy,iz)
        sum_lr_z=sum_lr_z+fw%pz_lr(ix,iy,iz)
      end do
      end do
      end do
!$omp end do
!$omp end parallel
      sum_lr(1)=sum_lr_x; sum_lr(2)=sum_lr_y; sum_lr(3)=sum_lr_z;
      call comm_summation(sum_lr,sum_lr2,3,nproc_group_global)
      fw%dip_lr(fw%iter_lr,:)=sum_lr2(:)*fs%hgs(1)*fs%hgs(2)*fs%hgs(3)
    elseif(yn_periodic=='y') then
      !initialize current density
!$omp parallel
!$omp do private(ix,iy,iz)
      do iz=fs%ng%is(3),fs%ng%ie(3)
      do iy=fs%ng%is(2),fs%ng%ie(2)
      do ix=fs%ng%is(1),fs%ng%ie(1)
        fw%rjx_lr(ix,iy,iz)=0.0d0; fw%rjy_lr(ix,iy,iz)=0.0d0; fw%rjz_lr(ix,iy,iz)=0.0d0;
      end do
      end do
      end do
!$omp end do
!$omp end parallel
      
      !add all current density
      if(fw%num_ld>0) then
!$omp parallel
!$omp do private(ix,iy,iz)
        do iz=fs%ng%is(3),fs%ng%ie(3)
        do iy=fs%ng%is(2),fs%ng%ie(2)
        do ix=fs%ng%is(1),fs%ng%ie(1)
          fw%rjx_lr(ix,iy,iz)=fw%rjx_lr(ix,iy,iz)+fw%rjx_sum_ld(ix,iy,iz)
          fw%rjy_lr(ix,iy,iz)=fw%rjy_lr(ix,iy,iz)+fw%rjy_sum_ld(ix,iy,iz)
          fw%rjz_lr(ix,iy,iz)=fw%rjz_lr(ix,iy,iz)+fw%rjz_sum_ld(ix,iy,iz)
        end do
        end do
        end do
!$omp end do
!$omp end parallel
      end if
      
      !calculate average current density
      sum_lr_x=0.0d0;  sum_lr_y=0.0d0;  sum_lr_z=0.0d0;
      sum_lr(:)=0.0d0; sum_lr2(:)=0.0d0;
!$omp parallel
!$omp do private(ix,iy,iz) reduction( + : sum_lr_x,sum_lr_y,sum_lr_z )
      do iz=fs%ng%is(3),fs%ng%ie(3)
      do iy=fs%ng%is(2),fs%ng%ie(2)
      do ix=fs%ng%is(1),fs%ng%ie(1)
        sum_lr_x=sum_lr_x+fw%rjx_lr(ix,iy,iz)
        sum_lr_y=sum_lr_y+fw%rjy_lr(ix,iy,iz)
        sum_lr_z=sum_lr_z+fw%rjz_lr(ix,iy,iz)
      end do
      end do
      end do
!$omp end do
!$omp end parallel
      sum_lr(1)=sum_lr_x; sum_lr(2)=sum_lr_y; sum_lr(3)=sum_lr_z;
      call comm_summation(sum_lr,sum_lr2,3,nproc_group_global)
      fw%curr_lr(fw%iter_lr,:)=sum_lr2(:)*fs%hgs(1)*fs%hgs(2)*fs%hgs(3) &
                               /(fs%rlsize(1)*fs%rlsize(2)*fs%rlsize(3))
      
      !calculate average electric field
      sum_lr_x=0.0d0;  sum_lr_y=0.0d0;  sum_lr_z=0.0d0;
      sum_lr(:)=0.0d0; sum_lr2(:)=0.0d0;
!$omp parallel
!$omp do private(ix,iy,iz) reduction( + : sum_lr_x,sum_lr_y,sum_lr_z )
      do iz=fs%ng%is(3),fs%ng%ie(3)
      do iy=fs%ng%is(2),fs%ng%ie(2)
      do ix=fs%ng%is(1),fs%ng%ie(1)
        sum_lr_x=sum_lr_x+( fw%ex_y(ix,iy,iz)+fw%ex_z(ix,iy,iz) )
        sum_lr_y=sum_lr_y+( fw%ey_z(ix,iy,iz)+fw%ey_x(ix,iy,iz) )
        sum_lr_z=sum_lr_z+( fw%ez_x(ix,iy,iz)+fw%ez_y(ix,iy,iz) )
      end do
      end do
      end do
!$omp end do
!$omp end parallel
      sum_lr(1)=sum_lr_x; sum_lr(2)=sum_lr_y; sum_lr(3)=sum_lr_z;
      call comm_summation(sum_lr,sum_lr2,3,nproc_group_global)
      fw%e_lr(fw%iter_lr,:)=sum_lr2(:)*fs%hgs(1)*fs%hgs(2)*fs%hgs(3) &
                            /(fs%rlsize(1)*fs%rlsize(2)*fs%rlsize(3))
    end if
    
    !update time iteration
    fw%iter_lr=fw%iter_lr+1
    
  end subroutine eh_calc_lr
  
  !=========================================================================================
  != add incident current source ===========================================================
  subroutine eh_add_inc(iord,amp,tw,omega,cep,ep_r,ep_i,aes,typ)
    implicit none
    integer,intent(in)       :: iord
    real(8),intent(in)       :: amp,tw,omega,cep
    real(8),intent(in)       :: ep_r(3),ep_i(3)
    character(16),intent(in) :: aes,typ
    real(8)                  :: t_sta,t,theta1,theta2_r,theta2_i,alpha,beta,gamma,tf_r,tf_i
    real(8)                  :: add_inc(3)
    
    !calculate time factor and adding current
    if(iord==1) then
      t_sta=t1_start
    elseif(iord==2) then
      t_sta=t1_start+t1_t2
    end if
    t=(dble(iter)-0.5d0)*dt_em-t_sta
    theta1=pi/tw*(t-0.5d0*tw)                         !for cos(theta1)**2
    alpha =pi/tw                                      !for cos(theta1)**2
    theta2_r=omega*(t-0.5d0*tw)+cep*2d0*pi            !for cos(theta2)
    theta2_i=omega*(t-0.5d0*tw)+cep*2d0*pi+3d0/2d0*pi !for cos(theta2), where this is translated to sin.
    beta=omega                                        !for cos(theta2)
    if(t>=0.0d0.and.t<=tw) then
      gamma=1.0d0
    else
      gamma=0.0d0
    end if
    if(aes=='Ecos2')then
      tf_r=cos(theta1)**2*cos(theta2_r)*gamma
      tf_i=cos(theta1)**2*cos(theta2_i)*gamma
    else if(aes=='Acos2')then
      tf_r=-(-alpha*sin(2.d0*theta1)*cos(theta2_r)   &
             -beta*cos(theta1)**2*sin(theta2_r))/beta*gamma
      tf_i=-(-alpha*sin(2.d0*theta1)*cos(theta2_i)   &
             -beta*cos(theta1)**2*sin(theta2_i))/beta*gamma
    end if
!    tf_r=exp(-0.5d0*(( ((dble(iter)-0.5d0)*dt_em-10.0d0*tw1)/tw1 )**2.0d0) ) !test time factor
    add_inc(:)=amp*(tf_r*ep_r(:)+tf_i*ep_i(:))
    
    if(typ=='point') then
      if(fw%inc_po_pe(iord)==1) then
        ix=fw%inc_po_id(iord,1); iy=fw%inc_po_id(iord,2); iz=fw%inc_po_id(iord,3);
        fw%ex_y(ix,iy,iz)=add_inc(1)/2.0d0
        fw%ex_z(ix,iy,iz)=add_inc(1)/2.0d0
        fw%ey_z(ix,iy,iz)=add_inc(2)/2.0d0
        fw%ey_x(ix,iy,iz)=add_inc(2)/2.0d0
        fw%ez_x(ix,iy,iz)=add_inc(3)/2.0d0
        fw%ez_y(ix,iy,iz)=add_inc(3)/2.0d0
      end if
    elseif(typ=='x-line') then
      if(fw%inc_li_pe(iord,1)==1) then
        iy=fw%inc_po_id(iord,2); iz=fw%inc_po_id(iord,3);
        fw%ex_y(fw%iex_y_is(1):fw%iex_y_ie(1),iy,iz)=add_inc(1)/2.0d0
        fw%ex_z(fw%iex_z_is(1):fw%iex_z_ie(1),iy,iz)=add_inc(1)/2.0d0
        fw%ey_z(fw%iey_z_is(1):fw%iey_z_ie(1),iy,iz)=add_inc(2)/2.0d0
        fw%ey_x(fw%iey_x_is(1):fw%iey_x_ie(1),iy,iz)=add_inc(2)/2.0d0
        fw%ez_x(fw%iez_x_is(1):fw%iez_x_ie(1),iy,iz)=add_inc(3)/2.0d0
        fw%ez_y(fw%iez_y_is(1):fw%iez_y_ie(1),iy,iz)=add_inc(3)/2.0d0
      end if
    elseif(typ=='y-line') then
      if(fw%inc_li_pe(iord,2)==1) then
        ix=fw%inc_po_id(iord,1); iz=fw%inc_po_id(iord,3);
        fw%ex_y(ix,fw%iex_y_is(2):fw%iex_y_ie(2),iz)=add_inc(1)/2.0d0
        fw%ex_z(ix,fw%iex_z_is(2):fw%iex_z_ie(2),iz)=add_inc(1)/2.0d0
        fw%ey_z(ix,fw%iey_z_is(2):fw%iey_z_ie(2),iz)=add_inc(2)/2.0d0
        fw%ey_x(ix,fw%iey_x_is(2):fw%iey_x_ie(2),iz)=add_inc(2)/2.0d0
        fw%ez_x(ix,fw%iez_x_is(2):fw%iez_x_ie(2),iz)=add_inc(3)/2.0d0
        fw%ez_y(ix,fw%iez_y_is(2):fw%iez_y_ie(2),iz)=add_inc(3)/2.0d0
      end if
    elseif(typ=='z-line') then
      if(fw%inc_li_pe(iord,3)==1) then
        ix=fw%inc_po_id(iord,1); iy=fw%inc_po_id(iord,2);
        fw%ex_y(ix,iy,fw%iex_y_is(3):fw%iex_y_ie(3))=add_inc(1)/2.0d0
        fw%ex_z(ix,iy,fw%iex_z_is(3):fw%iex_z_ie(3))=add_inc(1)/2.0d0
        fw%ey_z(ix,iy,fw%iey_z_is(3):fw%iey_z_ie(3))=add_inc(2)/2.0d0
        fw%ey_x(ix,iy,fw%iey_x_is(3):fw%iey_x_ie(3))=add_inc(2)/2.0d0
        fw%ez_x(ix,iy,fw%iez_x_is(3):fw%iez_x_ie(3))=add_inc(3)/2.0d0
        fw%ez_y(ix,iy,fw%iez_y_is(3):fw%iez_y_ie(3))=add_inc(3)/2.0d0
      end if
    elseif(typ=='xy-plane') then !z propagation !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      if(fw%inc_pl_pe(iord,1)==1) then
        iz=fw%inc_po_id(iord,3)
!$omp parallel
!$omp do private(ix,iy)
        do iy=fw%iex_z_is(2),fw%iex_z_ie(2)
        do ix=fw%iex_z_is(1),fw%iex_z_ie(1)
          fw%ex_z(ix,iy,iz)=fw%ex_z(ix,iy,iz)+fw%c2_inc_xyz(3)*add_inc(1)
        end do
        end do
!$omp end do
!$omp end parallel
!$omp parallel
!$omp do private(ix,iy)
        do iy=fw%iey_z_is(2),fw%iey_z_ie(2)
        do ix=fw%iey_z_is(1),fw%iey_z_ie(1)
          fw%ey_z(ix,iy,iz)=fw%ey_z(ix,iy,iz)+fw%c2_inc_xyz(3)*add_inc(2)
        end do
        end do
!$omp end do
!$omp end parallel
      end if
    elseif(typ=='yz-plane') then !x propagation !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      if(fw%inc_pl_pe(iord,2)==1) then
        ix=fw%inc_po_id(iord,1)
!$omp parallel
!$omp do private(iy,iz)
        do iz=fw%iey_x_is(3),fw%iey_x_ie(3)
        do iy=fw%iey_x_is(2),fw%iey_x_ie(2)
          fw%ey_x(ix,iy,iz)=fw%ey_x(ix,iy,iz)+fw%c2_inc_xyz(1)*add_inc(2)
        end do
        end do
!$omp end do
!$omp end parallel
!$omp parallel
!$omp do private(iy,iz)
        do iz=fw%iez_x_is(3),fw%iez_x_ie(3)
        do iy=fw%iez_x_is(2),fw%iez_x_ie(2)
          fw%ez_x(ix,iy,iz)=fw%ez_x(ix,iy,iz)+fw%c2_inc_xyz(1)*add_inc(3)
        end do
        end do
!$omp end do
!$omp end parallel
      end if
    elseif(typ=='xz-plane') then !y propagation !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      if(fw%inc_pl_pe(iord,3)==1) then
        iy=fw%inc_po_id(iord,2)
!$omp parallel
!$omp do private(ix,iz)
        do iz=fw%iex_y_is(3),fw%iex_y_ie(3)
        do ix=fw%iex_y_is(1),fw%iex_y_ie(1)
          fw%ex_y(ix,iy,iz)=fw%ex_y(ix,iy,iz)+fw%c2_inc_xyz(2)*add_inc(1)
        end do
        end do
!$omp end do
!$omp end parallel
!$omp parallel
!$omp do private(ix,iz)
        do iz=fw%iez_y_is(3),fw%iez_y_ie(3)
        do ix=fw%iez_y_is(1),fw%iez_y_ie(1)
          fw%ez_y(ix,iy,iz)=fw%ez_y(ix,iy,iz)+fw%c2_inc_xyz(2)*add_inc(3)
        end do
        end do
!$omp end do
!$omp end parallel
      end if
    end if
    
  end subroutine eh_add_inc
  
  !=========================================================================================
  != add current ===========================================================================
  subroutine eh_add_curr(rjx,rjy,rjz)
    implicit none
    real(8),intent(in) :: rjx(fs%ng%is_array(1):fs%ng%ie_array(1),&
                              fs%ng%is_array(2):fs%ng%ie_array(2),&
                              fs%ng%is_array(3):fs%ng%ie_array(3)),&
                          rjy(fs%ng%is_array(1):fs%ng%ie_array(1),&
                              fs%ng%is_array(2):fs%ng%ie_array(2),&
                              fs%ng%is_array(3):fs%ng%ie_array(3)),&
                          rjz(fs%ng%is_array(1):fs%ng%ie_array(1),&
                              fs%ng%is_array(2):fs%ng%ie_array(2),&
                              fs%ng%is_array(3):fs%ng%ie_array(3))
    
    !ex
!$omp parallel
!$omp do private(ix,iy,iz)
    do iz=fw%iex_y_is(3),fw%iex_y_ie(3)
    do iy=fw%iex_y_is(2),fw%iex_y_ie(2)
    do ix=fw%iex_y_is(1),fw%iex_y_ie(1)
      fw%ex_y(ix,iy,iz)=fw%ex_y(ix,iy,iz)+fw%c2_jx(ix,iy,iz)*rjx(ix,iy,iz)/2.0d0
    end do
    end do
    end do
!$omp end do
!$omp end parallel
!$omp parallel
!$omp do private(ix,iy,iz)
    do iz=fw%iex_z_is(3),fw%iex_z_ie(3)
    do iy=fw%iex_z_is(2),fw%iex_z_ie(2)
    do ix=fw%iex_z_is(1),fw%iex_z_ie(1)
      fw%ex_z(ix,iy,iz)=fw%ex_z(ix,iy,iz)+fw%c2_jx(ix,iy,iz)*rjx(ix,iy,iz)/2.0d0
    end do
    end do
    end do
!$omp end do
!$omp end parallel
    
    !ey
!$omp parallel
!$omp do private(ix,iy,iz)
    do iz=fw%iey_z_is(3),fw%iey_z_ie(3)
    do iy=fw%iey_z_is(2),fw%iey_z_ie(2)
    do ix=fw%iey_z_is(1),fw%iey_z_ie(1)
      fw%ey_z(ix,iy,iz)=fw%ey_z(ix,iy,iz)+fw%c2_jy(ix,iy,iz)*rjy(ix,iy,iz)/2.0d0
    end do
    end do
    end do
!$omp end do
!$omp end parallel
!$omp parallel
!$omp do private(ix,iy,iz)
    do iz=fw%iey_x_is(3),fw%iey_x_ie(3)
    do iy=fw%iey_x_is(2),fw%iey_x_ie(2)
    do ix=fw%iey_x_is(1),fw%iey_x_ie(1)
      fw%ey_x(ix,iy,iz)=fw%ey_x(ix,iy,iz)+fw%c2_jy(ix,iy,iz)*rjy(ix,iy,iz)/2.0d0
    end do
    end do
    end do
!$omp end do
!$omp end parallel
    
    !ez
!$omp parallel
!$omp do private(ix,iy,iz)
    do iz=fw%iez_x_is(3),fw%iez_x_ie(3)
    do iy=fw%iez_x_is(2),fw%iez_x_ie(2)
    do ix=fw%iez_x_is(1),fw%iez_x_ie(1)
      fw%ez_x(ix,iy,iz)=fw%ez_x(ix,iy,iz)+fw%c2_jz(ix,iy,iz)*rjz(ix,iy,iz)/2.0d0
    end do
    end do
    end do
!$omp end do
!$omp end parallel
!$omp parallel
!$omp do private(ix,iy,iz)
    do iz=fw%iez_y_is(3),fw%iez_y_ie(3)
    do iy=fw%iez_y_is(2),fw%iez_y_ie(2)
    do ix=fw%iez_y_is(1),fw%iez_y_ie(1)
      fw%ez_y(ix,iy,iz)=fw%ez_y(ix,iy,iz)+fw%c2_jz(ix,iy,iz)*rjz(ix,iy,iz)/2.0d0
    end do
    end do
    end do
!$omp end do
!$omp end parallel
    
  end subroutine eh_add_curr
  
  !=========================================================================================
  != check and update maximum of e and h ===================================================
  subroutine eh_update_max
    implicit none
    real(8) :: fe(fs%ng%is(1):fs%ng%ie(1),fs%ng%is(2):fs%ng%ie(2),fs%ng%is(3):fs%ng%ie(3)),&
               fh(fs%ng%is(1):fs%ng%ie(1),fs%ng%is(2):fs%ng%ie(2),fs%ng%is(3):fs%ng%ie(3))
    real(8) :: e_max_tmp(0:nproc_size_global-1), h_max_tmp(0:nproc_size_global-1),&
               e_max_tmp2(0:nproc_size_global-1),h_max_tmp2(0:nproc_size_global-1)
    
    e_max_tmp(:)=0.0d0; h_max_tmp(:)=0.0d0;
    do iz=fs%ng%is(3),fs%ng%ie(3)
    do iy=fs%ng%is(2),fs%ng%ie(2)
    do ix=fs%ng%is(1),fs%ng%ie(1)
      fe(ix,iy,iz)=sqrt( fw%ex_s(ix,iy,iz)**2.0d0 + fw%ey_s(ix,iy,iz)**2.0d0 + fw%ez_s(ix,iy,iz)**2.0d0 )
      fh(ix,iy,iz)=sqrt( fw%hx_s(ix,iy,iz)**2.0d0 + fw%hy_s(ix,iy,iz)**2.0d0 + fw%hz_s(ix,iy,iz)**2.0d0 )
      if(e_max_tmp(nproc_id_global)<fe(ix,iy,iz)) e_max_tmp(nproc_id_global)=fe(ix,iy,iz)
      if(h_max_tmp(nproc_id_global)<fh(ix,iy,iz)) h_max_tmp(nproc_id_global)=fh(ix,iy,iz)
    end do
    end do
    end do
    call comm_summation(e_max_tmp,e_max_tmp2,nproc_size_global,nproc_group_global)
    call comm_summation(h_max_tmp,h_max_tmp2,nproc_size_global,nproc_group_global)
    e_max_tmp2(:)=e_max_tmp2(:)*fw%uVperm_from_au
    h_max_tmp2(:)=h_max_tmp2(:)*fw%uAperm_from_au
    if(fw%e_max<maxval(e_max_tmp2(:))) fw%e_max=maxval(e_max_tmp2(:))
    if(fw%h_max<maxval(h_max_tmp2(:))) fw%h_max=maxval(h_max_tmp2(:))
    
  end subroutine eh_update_max
  
end subroutine eh_calc
