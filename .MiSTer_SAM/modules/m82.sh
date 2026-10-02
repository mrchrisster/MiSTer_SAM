# SPDX-License-Identifier: GPL-3.0-or-later
m82=yes
sam_mode=m82
source "$mrsampath/modules/m82-functions.sh"
source "$mrsampath/modules/compat-selection.sh"
source "$mrsampath/modules/compat-catalog.sh"
source "$mrsampath/modules/compat-loop.sh"
sam_bind session_loop loop_core
sam_register config_loaded build_m82_list
