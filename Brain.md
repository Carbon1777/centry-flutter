Зачем создали
Единое локальное хранилище знаний без Obsidian/облаков. Туда складываются YouTube, PDF, HTML, MD/TXT, DOCX, медиа, папки курсов → автоматически появляются:

sources/ — оригиналы (нельзя удалять без команды),
extracts/ — чистый текст,
knowledge/summaries/ — markdown-карточки на каждый источник,
indexes/ — навигация для агента,
personas/ — режимы ответа.
Это даёт «второй мозг», по которому любой агент может отвечать со ссылками на источник, а не «из общего знания».

Как этим пользуются другие сессии
1. Claude Code из любого VS Code-проекта
В нужном проекте создай/дополни CLAUDE.md строкой:

Knowledge base: /Users/jcat/Documents/Brain
Перед ответом по теме читай Brain/index.md → Brain/indexes/root.md.
Команды: cd /Users/jcat/Documents/Brain && .venv/bin/python scripts/kb.py {status|search "..."|add <path|url>|process}
Агент сам начнёт ходить в Brain через Read и Bash.

2. Cowork / любые сессии Claude Code (CLI, desktop, web)
То же самое, только глобально — добавь блок в ~/.claude/CLAUDE.md:

## Knowledge base
Brain: /Users/jcat/Documents/Brain
Точка входа: index.md → indexes/root.md.
CLI: /Users/jcat/Documents/Brain/.venv/bin/python /Users/jcat/Documents/Brain/scripts/kb.py
Тогда любая сессия (включая Cowork-плагины и subagents) знает про базу без копипасты.

3. NotebookLM (/strategic, /notebooklm)
Скилл /strategic уже льёт session-логи в твой «AI Brain» NotebookLM. Можно расширить: после /strategic дополнительно класть копию summary в /Users/jcat/Documents/Brain/inbox/ и звать kb.py process — тогда стратегические сессии оседают в локальной базе тоже.

4. Скрипты, скилы, MCP, scheduled-tasks
Любой инструмент, умеющий запускать shell, дергает kb.py:

add <url|file|folder> — закинуть материал,
search "..." — найти,
status — проверить здоровье базы,
rebuild-index — пересобрать навигацию.
Например, /schedule может раз в неделю прогонять process по inbox/, а Chrome-MCP — кидать туда сохранённые статьи.

5. Subagents (Explore, general-purpose, Plan)
В промпте субагенту указывай: «сначала проверь /Users/jcat/Documents/Brain через kb.py search "..." и Read summary-файлов, прежде чем искать в коде/вебе». Так база становится первым слоем поиска.

Главный смысл
Brain — это общая внешняя память для всей твоей Claude-инфраструктуры: VS Code-проекты, Cowork, NotebookLM, MCP, скилы, scheduled agents. Все они пишут туда через kb.py add и читают через Read + kb.py search. Один источник правды, локально, под твоим контролем.

Хочешь — пропишу блок про Brain в ~/.claude/CLAUDE.md, чтобы все будущие сессии его сразу видели?