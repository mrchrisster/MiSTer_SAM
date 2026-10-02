# SPDX-License-Identifier: GPL-3.0-or-later
# The existing menu writes trusted roulette settings; normal queued selection
# handles its timer and core policy. No auxiliary loop/process is required.
sam_mode=roulette
[[ ! -f "$mrsamtmp/gameroulette.ini" ]] || source "$mrsamtmp/gameroulette.ini"
