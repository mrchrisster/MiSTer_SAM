# SPDX-License-Identifier: GPL-3.0-or-later
"""Process-local monitor overrides; a new INI value takes precedence."""
KEYS=('listenjoy','listenkeyboard','listenmouse','samdebug')


class InputOptions:
    def __init__(self, base):
        self.base={key:bool(base[key]) for key in KEYS}
        self.overrides={}

    def update_ini(self, base):
        for key in KEYS:
            value=bool(base[key])
            if value!=self.base[key]:self.overrides.pop(key,None)
            self.base[key]=value

    def toggle(self, key):
        if key not in KEYS:raise ValueError('Unknown input option')
        self.overrides[key]=not self.effective()[key]

    def reset(self):
        self.overrides.clear()

    def effective(self):
        return dict(self.base,**self.overrides)
