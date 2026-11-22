#!/usr/bin/env bash
set -eu

task="${1:?Indica assemble, test ou integrationTest}"
case "$task" in
  assemble|test|integrationTest) ;;
  *) echo 'Tarefa Gradle não suportada.' >&2; exit 2 ;;
esac

export JAVA_HOME="${JAVA17_HOME:-${JAVA_HOME:?Configura JAVA17_HOME ou JAVA_HOME}}"
export PATH="$JAVA_HOME/bin:$PATH"
started="$(date +%s.%N)"
chmod +x gradlew

set +e
if [ "$task" = assemble ]; then
  ./gradlew clean assemble --no-daemon --console=plain --max-workers=1 \
    '-Dorg.gradle.jvmargs=-Xmx256m -XX:MaxMetaspaceSize=256m'
else
  # Classes e recursos de main vêm do stage Assemble, copiados pelo stash.
  ./gradlew "$task" -x compileJava -x processResources \
    --no-daemon --console=plain --max-workers=1 \
    '-Dorg.gradle.jvmargs=-Xmx256m -XX:MaxMetaspaceSize=256m'
fi
result=$?
set -e

mkdir -p app/build/ci
python3 - "$task" "$started" "$(date +%s.%N)" "$result" <<'PY' > "app/build/ci/$task-timing.json"
import json
import sys
task, started, finished, result = sys.argv[1:]
json.dump({'task': task, 'started_epoch': float(started),
           'finished_epoch': float(finished), 'exit_code': int(result)}, sys.stdout, indent=2)
print()
PY
exit "$result"
