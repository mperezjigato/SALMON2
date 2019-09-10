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
!--------10--------20--------30--------40--------50--------60--------70--------80--------90--------100-------110-------120--------
module init_poisson_sub
  implicit none

contains

!=====================================================================
subroutine make_corr_pole(lg,ng,poisson)
  use inputoutput, only: natom,Rion,layout_multipole,num_multipole_xyz
  use structures, only: s_rgrid,s_poisson
  implicit none
  type(s_rgrid), intent(in) :: lg
  type(s_rgrid), intent(in) :: ng
  type(s_poisson),intent(inout) :: poisson
  integer :: a,i
  integer :: ix,iy,iz
  integer :: ibox
  integer :: j1,j2,j3
  integer,allocatable :: ista_Mxin_pole(:,:)
  integer,allocatable :: iend_Mxin_pole(:,:)
  integer,allocatable :: inum_Mxin_pole(:,:)
  integer,allocatable :: iflag_pole(:)
  integer :: amin,amax
  real(8) :: rmin,r
  real(8),allocatable :: Rion2(:,:)
  integer,allocatable :: nearatomnum(:,:,:)
  integer,allocatable :: inv_icorr_polenum(:)
  integer :: maxval_ig_num

  if(layout_multipole==2)then
  
    amax=natom
    allocate(Rion2(3,natom))
    Rion2(:,:)=Rion(:,:)
  
    allocate(poisson%ig_num(1:amax))
    allocate(nearatomnum(ng%is(1):ng%ie(1),ng%is(2):ng%ie(2),ng%is(3):ng%ie(3)))
    poisson%ig_num=0
    do iz=ng%is(3),ng%ie(3)
    do iy=ng%is(2),ng%ie(2)
    do ix=ng%is(1),ng%ie(1)
      rmin=1.d6
      do a=1,amax
        r=sqrt( (lg%coordinate(ix,1)-Rion2(1,a))**2      &
              + (lg%coordinate(iy,2)-Rion2(2,a))**2      &
              + (lg%coordinate(iz,3)-Rion2(3,a))**2 )
        if ( r < rmin ) then
          rmin=r ; amin=a
        end if
      end do
      poisson%ig_num(amin)=poisson%ig_num(amin)+1
      nearatomnum(ix,iy,iz)=amin
    end do
    end do
    end do
  
    allocate(poisson%ipole_tbl(1:amax))
    allocate(inv_icorr_polenum(1:amax))
    poisson%ipole_tbl=0
    inv_icorr_polenum=0
    ibox=0
    do a=1,amax
      if(poisson%ig_num(a)>=1)then
        ibox=ibox+1
        poisson%ipole_tbl(ibox)=a
        inv_icorr_polenum(a)=ibox
      end if
    end do
    poisson%npole_partial=ibox
  
    maxval_ig_num=maxval(poisson%ig_num(:)) 
    allocate(poisson%ig(3,maxval(poisson%ig_num(:)),poisson%npole_partial))
  
    poisson%ig_num(:)=0
  
    do iz=ng%is(3),ng%ie(3)
    do iy=ng%is(2),ng%ie(2)
    do ix=ng%is(1),ng%ie(1)
      ibox=inv_icorr_polenum(nearatomnum(ix,iy,iz))
      poisson%ig_num(ibox)=poisson%ig_num(ibox)+1
      poisson%ig(1,poisson%ig_num(ibox),ibox)=ix
      poisson%ig(2,poisson%ig_num(ibox),ibox)=iy
      poisson%ig(3,poisson%ig_num(ibox),ibox)=iz
    end do
    end do
    end do
  
    deallocate(Rion2)
    deallocate(nearatomnum)
    deallocate(inv_icorr_polenum)
  
  else if(layout_multipole==3)then
  
    allocate(ista_Mxin_pole(3,0:poisson%npole_total-1))
    allocate(iend_Mxin_pole(3,0:poisson%npole_total-1))
    allocate(inum_Mxin_pole(3,0:poisson%npole_total-1))
    allocate(iflag_pole(1:poisson%npole_total))
  
    do j3=0,num_multipole_xyz(3)-1
    do j2=0,num_multipole_xyz(2)-1
    do j1=0,num_multipole_xyz(1)-1
      ibox = j1 + num_multipole_xyz(1)*j2 + num_multipole_xyz(1)*num_multipole_xyz(2)*j3 
      ista_Mxin_pole(1,ibox)=j1*lg%num(1)/num_multipole_xyz(1)+lg%is(1)
      iend_Mxin_pole(1,ibox)=(j1+1)*lg%num(1)/num_multipole_xyz(1)+lg%is(1)-1
      ista_Mxin_pole(2,ibox)=j2*lg%num(2)/num_multipole_xyz(2)+lg%is(2)
      iend_Mxin_pole(2,ibox)=(j2+1)*lg%num(2)/num_multipole_xyz(2)+lg%is(2)-1
      ista_Mxin_pole(3,ibox)=j3*lg%num(3)/num_multipole_xyz(3)+lg%is(3)
      iend_Mxin_pole(3,ibox)=(j3+1)*lg%num(3)/num_multipole_xyz(3)+lg%is(3)-1
    end do
    end do
    end do
  
    iflag_pole=0
  
    do iz=ng%is(3),ng%ie(3)
    do iy=ng%is(2),ng%ie(2)
    do ix=ng%is(1),ng%ie(1)
      do i=1,poisson%npole_total
        if(ista_Mxin_pole(3,i-1)<=iz.and.iend_Mxin_pole(3,i-1)>=iz.and.   &
           ista_Mxin_pole(2,i-1)<=iy.and.iend_Mxin_pole(2,i-1)>=iy.and.   &
           ista_Mxin_pole(1,i-1)<=ix.and.iend_Mxin_pole(1,i-1)>=ix)then
          iflag_pole(i)=1
        end if
      end do
    end do
    end do
    end do
  
    poisson%npole_partial=0
    do i=1,poisson%npole_total
      if(iflag_pole(i)==1)then
        poisson%npole_partial=poisson%npole_partial+1
      end if
    end do
  
    allocate(poisson%ipole_tbl(1:poisson%npole_partial))
    allocate(poisson%ig_num(1:poisson%npole_partial))
  
    ibox=1
    do i=1,poisson%npole_total
      if(iflag_pole(i)==1)then
        poisson%ipole_tbl(ibox)=i
        ibox=ibox+1
      end if
    end do
  
    poisson%ig_num=0
  
    do iz=ng%is(3),ng%ie(3)
    do iy=ng%is(2),ng%ie(2)
    do ix=ng%is(1),ng%ie(1)
      do i=1,poisson%npole_partial
        if(ista_Mxin_pole(3,poisson%ipole_tbl(i)-1)<=iz.and.iend_Mxin_pole(3,poisson%ipole_tbl(i)-1)>=iz.and.   &
           ista_Mxin_pole(2,poisson%ipole_tbl(i)-1)<=iy.and.iend_Mxin_pole(2,poisson%ipole_tbl(i)-1)>=iy.and.   &
           ista_Mxin_pole(1,poisson%ipole_tbl(i)-1)<=ix.and.iend_Mxin_pole(1,poisson%ipole_tbl(i)-1)>=ix)then
          poisson%ig_num(i)=poisson%ig_num(i)+1
        end if
      end do
    end do
    end do
    end do
  
    maxval_ig_num=maxval(poisson%ig_num(:)) 
    allocate(poisson%ig(3,maxval(poisson%ig_num(:)),poisson%npole_partial))
   
    poisson%ig_num=0
  
    do iz=ng%is(3),ng%ie(3)
    do iy=ng%is(2),ng%ie(2)
    do ix=ng%is(1),ng%ie(1)
      do i=1,poisson%npole_partial
        if(ista_Mxin_pole(3,poisson%ipole_tbl(i)-1)<=iz.and.iend_Mxin_pole(3,poisson%ipole_tbl(i)-1)>=iz.and.   &
           ista_Mxin_pole(2,poisson%ipole_tbl(i)-1)<=iy.and.iend_Mxin_pole(2,poisson%ipole_tbl(i)-1)>=iy.and.   &
           ista_Mxin_pole(1,poisson%ipole_tbl(i)-1)<=ix.and.iend_Mxin_pole(1,poisson%ipole_tbl(i)-1)>=ix)then
          poisson%ig_num(i)=poisson%ig_num(i)+1
          poisson%ig(1,poisson%ig_num(i),i)=ix
          poisson%ig(2,poisson%ig_num(i),i)=iy
          poisson%ig(3,poisson%ig_num(i),i)=iz
        end if
      end do
    end do
    end do
    end do
  
    deallocate(ista_Mxin_pole,iend_Mxin_pole,inum_Mxin_pole)
    deallocate(iflag_pole)
  
  end if

  return
 
end subroutine make_corr_pole

!=====================================================================

subroutine set_ig_bound(lg,ng,poisson)
  use structures, only: s_rgrid,s_poisson
  implicit none
  type(s_rgrid), intent(in)     :: lg, ng
  type(s_poisson),intent(inout) :: poisson
  integer :: ix,iy,iz
  integer :: ibox
  integer :: icount
  integer,parameter :: ndh=4
  
  ibox=ng%num(1)*ng%num(2)*ng%num(3)/minval(ng%num(1:3))*2*ndh
  allocate( poisson%ig_bound(3,ibox,3) )
  
  icount=0
  do iz=ng%is(3),ng%ie(3)
  do iy=ng%is(2),ng%ie(2)
  do ix=lg%is(1)-ndh,lg%is(1)-1
    icount=icount+1
    poisson%ig_bound(1,icount,1)=ix
    poisson%ig_bound(2,icount,1)=iy
    poisson%ig_bound(3,icount,1)=iz
  end do
  end do
  end do
  do iz=ng%is(3),ng%ie(3)
  do iy=ng%is(2),ng%ie(2)
  do ix=lg%ie(1)+1,lg%ie(1)+ndh
    icount=icount+1
    poisson%ig_bound(1,icount,1)=ix
    poisson%ig_bound(2,icount,1)=iy
    poisson%ig_bound(3,icount,1)=iz
  end do
  end do
  end do
  icount=0
  do iz=ng%is(3),ng%ie(3)
  do iy=lg%is(2)-ndh,lg%is(2)-1
  do ix=ng%is(1),ng%ie(1)
    icount=icount+1
    poisson%ig_bound(1,icount,2)=ix
    poisson%ig_bound(2,icount,2)=iy
    poisson%ig_bound(3,icount,2)=iz
  end do
  end do
  end do
  do iz=ng%is(3),ng%ie(3)
  do iy=lg%ie(2)+1,lg%ie(2)+ndh
  do ix=ng%is(1),ng%ie(1)
    icount=icount+1
    poisson%ig_bound(1,icount,2)=ix
    poisson%ig_bound(2,icount,2)=iy
    poisson%ig_bound(3,icount,2)=iz
  end do
  end do
  end do
  icount=0
  do iz=lg%is(3)-ndh,lg%is(3)-1
  do iy=ng%is(2),ng%ie(2)
  do ix=ng%is(1),ng%ie(1)
    icount=icount+1
    poisson%ig_bound(1,icount,3)=ix
    poisson%ig_bound(2,icount,3)=iy
    poisson%ig_bound(3,icount,3)=iz
  end do
  end do
  end do
  do iz=lg%ie(3)+1,lg%ie(3)+ndh
  do iy=ng%is(2),ng%ie(2)
  do ix=ng%is(1),ng%ie(1)
    icount=icount+1
    poisson%ig_bound(1,icount,3)=ix
    poisson%ig_bound(2,icount,3)=iy
    poisson%ig_bound(3,icount,3)=iz
  end do
  end do
  end do
  
  return

end subroutine set_ig_bound

!=====================================================================

subroutine init_poisson_fft(lg,ng,system,info_field,poisson)
  use math_constants, only : pi
  use structures,     only: s_rgrid,s_dft_system,s_field_parallel,s_poisson
  implicit none
  type(s_rgrid),intent(in) :: lg
  type(s_rgrid),intent(in) :: ng
  type(s_dft_system),intent(in) :: system
  type(s_field_parallel),intent(in) :: info_field
  type(s_poisson),intent(inout) :: poisson
  integer :: ng_sta_2(3),ng_end_2(3),ng_num_2(3)
  integer :: lg_sta_2(3),lg_end_2(3),lg_num_2(3)
  real(8) :: Gx,Gy,Gz
  real(8) :: G2
  integer :: kx,ky,kz
  integer :: kkx,kky,kkz
  integer :: ky2,kz2
  integer :: n
  integer :: kx_sta,kx_end,ky_sta,ky_end,kz_sta,kz_end
  real(8) :: bLx,bLy,bLz
  integer :: ky_shift,kz_shift
  
  integer :: npuy,npuz

  npuy=info_field%isize_ffte(2)
  npuz=info_field%isize_ffte(3)

  if(.not.allocated(poisson%coef))then
    allocate(poisson%coef(lg%num(1),lg%num(2)/npuy,lg%num(3)/npuz))
  end if
  poisson%coef=0.d0

  lg_sta_2(1:3)=lg%is(1:3)
  lg_end_2(1:3)=lg%ie(1:3)
  lg_num_2(1:3)=lg%num(1:3)
  
  ng_sta_2(1:3)=ng%is(1:3)
  ng_end_2(1:3)=ng%ie(1:3)
  ng_num_2(1:3)=ng%num(1:3)

  bLx=2.d0*pi/(system%hgs(1)*dble(lg_num_2(1)))
  bLy=2.d0*pi/(system%hgs(2)*dble(lg_num_2(2)))
  bLz=2.d0*pi/(system%hgs(3)*dble(lg_num_2(3)))
  
  kx_sta=lg_sta_2(1)
  kx_end=lg_end_2(1)
  ky_sta=1
  ky_end=lg_num_2(2)/npuy
  kz_sta=1
  kz_end=lg_num_2(3)/npuz

  ky_shift=info_field%id_ffte(2)*lg_num_2(2)/npuy
  kz_shift=info_field%id_ffte(3)*lg_num_2(3)/npuz

  do kz = kz_sta,kz_end
  do ky = ky_sta,ky_end
  do kx = kx_sta,kx_end
    ky2=ky+ky_shift
    kz2=kz+kz_shift
    n=(kz2-lg_sta_2(3))*lg_num_2(2)*lg_num_2(1)+(ky2-lg_sta_2(2))*lg_num_2(1)+kx-lg_sta_2(1)+1
    kkx=kx-1-lg_num_2(1)*(1+sign(1,(kx-1-lg_num_2(1)/2)))/2
    kky=ky2-1-lg_num_2(2)*(1+sign(1,(ky2-1-lg_num_2(2)/2)))/2
    kkz=kz2-1-lg_num_2(3)*(1+sign(1,(kz2-1-lg_num_2(3)/2)))/2
    Gx=dble(kkx)*bLx
    Gy=dble(kky)*bLy
    Gz=dble(kkz)*bLz
    G2=Gx**2+Gy**2+Gz**2
    if(kx==1.and.ky2==1.and.kz2==1)then
      poisson%coef(kx,ky,kz)=0.d0
    else
      poisson%coef(kx,ky,kz)=4.d0*pi/G2
    end if
  end do
  end do
  end do

  
  return
end subroutine init_poisson_fft

!--------10--------20--------30--------40--------50--------60--------70--------80--------90--------100-------110-------120--------

end module init_poisson_sub