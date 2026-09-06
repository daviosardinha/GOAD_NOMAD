"""Durable, observational records for individual installation attempts."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import tempfile
import time
from uuid import uuid4


def new_install_profile(provider_path):
    now = datetime.now(timezone.utc)
    attempt_id = now.strftime('%Y%m%dT%H%M%SZ') + '-' + uuid4().hex[:12]
    instance = Path(provider_path).parent
    return {
        'schema_version': 1,
        'attempt_id': attempt_id,
        'instance_id': instance.name,
        'started_at': now.isoformat(),
        'started': time.monotonic(),
        'status': 'provider_running',
        'phases': [],
        'ansible_phases': [],
        'provider_success': False,
        'measurement': 'One invocation from provider start through finalization; '
                       'nested phases overlap. Other attempts, manual recovery, '
                       'and gaps between invocations are excluded.',
        '_path': str(instance / 'install-timings' / (attempt_id + '.json')),
    }


def save_install_profile(profile, warn):
    """Checkpoint atomically; a timing-write failure must not affect lifecycle."""
    temporary = None
    try:
        destination = Path(profile['_path'])
        destination.parent.mkdir(parents=True, exist_ok=True)
        snapshot = {key: value for key, value in profile.items()
                    if not key.startswith('_') and key not in ('started', 'finished')}
        end = profile.get('finished')
        if end is None:
            end = time.monotonic()
        snapshot['recorded_elapsed'] = max(0, end - profile['started'])
        snapshot['updated_at'] = datetime.now(timezone.utc).isoformat()
        snapshot['partial'] = profile['status'] not in ('completed', 'failed', 'interrupted')
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8',
                                         dir=destination.parent, delete=False) as handle:
            temporary = handle.name
            json.dump(snapshot, handle, indent=2, allow_nan=False)
            handle.write('\n')
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, destination)
        temporary = None
        return True
    except (OSError, ValueError, TypeError) as exc:
        if not profile.get('_write_warning_emitted'):
            profile['_write_warning_emitted'] = True
            warn(f'GOAD Kingdoms: could not save installation timing: {exc}')
        return False
    finally:
        if temporary is not None:
            try:
                os.unlink(temporary)
            except OSError:
                pass
