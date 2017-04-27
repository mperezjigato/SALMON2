! Copyright 2017 Katsuyuki Nobusada, Masashi Noda, Kazuya Ishimura, Kenji Iida, Maiku Yamaguchi
!
! Licensed under the Apache License, Version 2.0 (the "License");
! you may not use this file except in compliance with the License.
! You may obtain a copy of the License at
!
!     http://www.apache.org/licenses/LICENSE-2.0
!
! Unless required by applicable law or agreed to in writing, software
! distributed under the License is distributed on an "AS IS" BASIS,
! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
! See the License for the specific language governing permissions and
! limitations under the License.

subroutine deallocate_sendrecv_groupob
use scf_data
use allocate_sendrecv_groupob_sub
implicit none

if(iSCFRT==1.and.icalcforce==1)then
  deallocate(srmatbox1_x,srmatbox1_y,srmatbox1_z)
  deallocate(srmatbox2_x,srmatbox2_y,srmatbox2_z)
  deallocate(srmatbox3_x,srmatbox3_y,srmatbox3_z)
  deallocate(srmatbox4_x,srmatbox4_y,srmatbox4_z)
  
end if

end subroutine deallocate_sendrecv_groupob
