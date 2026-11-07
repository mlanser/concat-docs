# all.just — the one file a project imports: `import '.just/all.just'`
#
# VENDORED from mlanser/f451labs-templates (just/). Do not edit in a project repo.
# The importing justfile must define `setup` and `check`.

import 'trunk.just'
import 'ci.just'
import 'secrets.just'
import 'container.just'
