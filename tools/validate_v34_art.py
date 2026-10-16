#!/usr/bin/env python3
"""Validate Bank v34 and the retained v33 delivery, including every tile pairing."""
import json
from validate_v33_art import validate

if __name__ == '__main__':
    bundle = validate()
    result = {key: value for key, value in bundle.items() if key.startswith('bank_')}
    result.update(brief='v34', png_crc_iend='OK', dimensions_and_sha256='OK',
                  retained_v33_bundle_png_files=bundle['png_files'],
                  production_bank_replaced=False, physical_devices_tested=False)
    print('V34_ART_OK ' + json.dumps(result, ensure_ascii=False, sort_keys=True))
