"""Publica contagens JUnit no resumo do job, mantendo os XML como artefactos."""
import os
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

directory = Path(sys.argv[1])
reports = sorted(directory.glob('*.xml'))
totals = {name: 0 for name in ('tests', 'failures', 'errors', 'skipped')}
for report in reports:
    suite = ET.parse(report).getroot()
    for name in totals:
        totals[name] += int(suite.get(name, 0))
summary = f"### Resultados: {directory.name}\n\n"
if not reports:
    summary += 'Não foram produzidos relatórios XML; consulta o resultado do passo Gradle.\n'
else:
    summary += '| Testes | Falhas | Erros | Ignorados |\n|---:|---:|---:|---:|\n'
    summary += '| ' + ' | '.join(str(totals[name]) for name in totals) + ' |\n'
with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a', encoding='utf-8') as output:
    output.write(summary)
print(summary)
