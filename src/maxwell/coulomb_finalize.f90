!
!  Copyright 2018 SALMON developers
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
subroutine coulomb_finalize(fs,ff,fw)
  use structures,     only: s_fdtd_system, s_fdtd_field
  use salmon_maxwell, only: s_fdtd_work
  implicit none
  type(s_fdtd_system) :: fs
  type(s_fdtd_field)  :: ff
  type(s_fdtd_work)   :: fw
  
end subroutine coulomb_finalize
