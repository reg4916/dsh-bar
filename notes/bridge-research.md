# DSH Bar — разведка моста host-плагин ↔ нативное меню-бар приложение

Задача: task-6. Статус: выполнено (разведка). Автор: bridge-scout. Дата: 2026-10-27.

**Что проверено и на чём:** референс «/tmp/dsh-notch-ref» (клон «aa2246740/dsh-notch», версия 0.3.6)
прочитан по существу: «src/*.ts», «macos/Sources/*.swift», «desktop/notch-lifecycle.mjs», «docs/», «README.md».
DSH-сторона проверена **не по референсу, а по установленному приложению**:
«/Applications/DeepSeek Harness.app/Contents/Resources/app.asar» (пакет «@deepseek-ai/dsh-desktop-runtime 0.2.1-rc.3»).
Метод: asar распарсен вручную (header JSON + offsets), затем прочитаны «README.md», «lib/*.js», «lib/typert.host.js»
нужных пакетов и сгенерированные декларации типов в «dsh-api-session-controller/lib/typert.host.js»
(там лежит полный «SessionEventMap» и все wire-типы). Динамика проверена на живом Desktop-процессе:
GUI http://127.0.0.1:49399, «/» и «/api» без токена отдают **401**, «CFBundleIdentifier» = «com.deepseek.dsh».

> **Ключевое расхождение, которое нельзя игнорировать:** dsh-notch 0.3.4 объявляет peer
> «>=0.2.0-rc.1 <0.2.1» и целится в «dsh-v0.2.0-rc.2», а установлен «0.2.1-rc.3» (вне диапазона).
> Поэтому API ниже — то, что реально есть в 0.2.1-rc.3; референс используется только как образец архитектуры.

---

## (a) Как устроен notch

### Схема

~~~
DSH Host (node, профиль desktop/web)
├─ плагин dsh-notch            src/dsh-notch.ts   (host half, ESM, Cordis)
│   ├─ store.ts                ~/.dsh/dsh-notch/runtime.json + seen.json
│   ├─ board.ts                состояние сессий, удержание approval/ask
│   └─ http.ts                 loopback HTTP + SSE на ctx.webServer, префикс /dsh-notch
│        ▲ Bearer token из runtime.json
│        │
├─ плагин dsh-notch-focus      src/client/index.ts  (browser half)
│        │ GET /dsh-notch/pending-focus (same-origin/bridge trust, без токена)
│        └─ ctx.uiWorkspace.openSession(sessionId) → открывает диалог в GUI
│
└─ нативное приложение (Swift, AppKit/SwiftUI, accessory/LSUIElement)
    ├─ Client.swift             читает runtime.json, GET /dsh-notch/status, POST /approve|/answer|/seen|/focus
    ├─ HostLifetime.swift       следит за pid из runtime.json и закрывается, когда Host умер
    └─ main.swift               панель у верхнего края, hover-раскрытие
~~~

### Транспорт

**Loopback HTTP + JSON + SSE**, монтируемый в уже существующий «ctx.webServer»:
«ctx.webServer.register({ kind: 'prefix', path: '/dsh-notch', handler })» («src/http.ts:174»).
Никакого unix-сокета и length-prefixed framing'а нет. Адрес («origin») и токен плагин пишет в
«runtime.json», нативная сторона их читает.

SSE — опциональный канал («GET /dsh-notch/events», «text/event-stream», первым кадром полный снапшот
«data: {...}»). Но нативное приложение notch **SSE не использует**: оно поллит «GET /dsh-notch/status»
каждые **0.8 с** («macos/Sources/RootView.swift:185-193», «Timer(timeInterval: 0.8)», tolerance 0.2).

### runtime.json (точная схема notch)

«src/store.ts:9-13»:

~~~ts
export const DIR = join(resolveDshHome(), 'dsh-notch')
export const RUNTIME = join(DIR, 'runtime.json')
export interface RuntimeFile { origin: string; token: string; pid: number; writtenAt: number }
~~~

Запись («src/dsh-notch.ts:26-32»): каталог «mkdirSync(..., mode 0o700)», файл «mode 0o600»,
содержимое «{ origin: `http://${ctx.webServer.host}:${ctx.webServer.port}`, token, pid: process.pid, writtenAt }».
Токен: «randomBytes(24).toString('hex')», переиспользуется из существующего файла, если «length >= 16».

### Авторизация и «браузерное» доверие

«src/http.ts»:

- «isLoopback(req)» — remoteAddress ∈ 127.0.0.1 / ::1 / ::ffff:127.0.0.1;
- «authorized(req, token)» — «Authorization: Bearer <token>» **или** «?token=» в query;
- всё, что не «/pending-focus» и не «/sidebar», требует loopback+token, иначе 403;
- «browserTrusted(req)» — loopback, «sec-fetch-site !== 'cross-site'», «Origin» отсутствует либо совпадает
  с «Host» (то есть страница GUI «своя»);
- «sidebarTrusted(req)» — fallback под Desktop: «content-type: application/json», «Origin» нет,
  «sec-fetch-site» нет, «x-dsh-notch-client: 1», «Host» совпадает с origin плагина.

Это не эвристика: Electron-шелл Desktop пересылает запросы страницы «dsh-app://app/<path>» в Host через
«forwardWebRequest» («app.asar/lib/main.js»), **удаляя** «host, origin, cookie, sec-fetch-site» и подставляя
host-cookie (см. (e) п.6).

### События и состояние (как notch получает данные)

«src/dsh-notch.ts:15-70»:

~~~ts
export const inject = ['sessions', 'webServer', 'approval', 'userQuestions', 'agents']
...
ctx.effect(() => ctx.on('session/created', notify))
ctx.effect(() => ctx.on('session/disposed', notify))
ctx.effect(() => ctx.on('session/event', (session, event) => {
  if (event.type === 'turn/end') board.noteTurnEnd(session, event.time)
  if (event.type === 'turn/start' || event.type === 'turn/end' || event.type === 'session/title') notify()
  if (event.type === 'turn/start' || (event.type === 'user/message' && event.data?.source === 'user')) board.markSeen(session.id)
}))
ctx.effect(() => ctx.on('agent/status', notify))
ctx.on('user-questions/request', (request, next) => board.holdAsk(request, next), { prepend: true })
~~~

«notify» — debounce 80 мс; он лишь дергает «board.bump()», а снапшот строится лениво в
«board.snapshot(origin)» при «GET /status» / SSE-push.

Состояние busy берётся **не** из сессионных событий, а из реестра агентов:
«board.ts:356-358»: «this.ctx.agents.get(session.id)?.status === 'running'».
Свёртка turn'ов («src/session-state.ts») — по «session.snapshotEvents()»: «turn/start» → busy,
«turn/end» → «lastTurn = { at, kind: event.data.reason.kind, failed: FAILED.has(kind) }»,
«FAILED = new Set(['error','blocked','max-tokens'])».
Дочерние сессии: «session.header.origin === 'subagent'», владелец — идти по «header.parentSession» до корня
(пользовательский fork остаётся самостоятельным разговором — «parentSession» есть и у fork).

### Approvals и вопросы

- **Вопросы (AskUserQuestion)** — waterfall-листенер «user-questions/request» с «{ prepend: true }»,
  возвращает «Promise<{ answers }>», удерживая запрос до ответа из notch («board.ts:320-354», «holdAsk»).
  Тонкости, которые нельзя потерять: внутри запроса переписывается «request.signal» на
  «AbortSignal.any([original, downstream])», а по завершении гонки зовётся «downstream.abort()» — иначе
  Web-панель вопроса останется висеть; исходный «request.signal» восстанавливается.
- **Approvals** — код «holdApproval» («board.ts:296-318») есть, но **в текущем notch не подключён**:
  в «dsh-notch.ts:58-60» комментарий «Do NOT intercept internal tool approval/request which causes
  false alarms when background agent tools run sandbox checks». То есть approvals остаются на GUI.
- Wire-формат ответа на approval в notch: «'allowed-once' | 'rejected'» (подмножество полного словаря, см. (b)).

### Как плагин запускает/гасит helper

«src/dsh-notch.ts:33-42»: конфиг «helperPath» (по умолчанию пустая строка); если задан и файл существует —
«ctx.effect(() => { const helper = superviseNotch({ bin, pidPath: join(DIR,'helper.pid'), log, env:
{...process.env, DSH_NOTCH_RUNTIME_FILE: RUNTIME} }); return () => { helper.stop(); log.end() } })».

«desktop/notch-lifecycle.mjs:superviseNotch» — полноценный супервизор: интервал 250 мс, identity по
«ps -p <pid> -o lstart= -o comm=» (PID + start-time + command, чтобы не убить чужой процесс с тем же pid),
adopt по «helper.pid», респавн не более 3 раз за 10 с, lease «helper.pid.updating» (60 с) для внешних
установщиков, при «stop()» — SIGTERM только своим (identity-checked) процессам.
Нативная сторона **не** запускает Host: она умирает вместе с ним — «macos/Sources/HostLifetime.swift»
следит за «pid» из runtime.json, «DispatchSource.makeProcessSource(.exit)» + grace, и делает «terminate(nil)».
HTTP-ошибки не считаются смертью Host.

---

## (b) Доступные DSH события/сервисы (проверено в 0.2.1-rc.3)

### Сервисы (Cordis ctx.<key>)

| Сервис | Пакет | Что даёт | Доказательство |
|---|---|---|---|
| «ctx.sessions» | «dsh-session» | «create/get/list/fork/flush»; «list()» — живые сессии в порядке создания | «super(ctx,'sessions')» |
| «ctx.agents» | «dsh-agent» | «get(id)/list()/roots()», «Agent.status: 'idle'|'running'», «cancel(cause,{keepInbox})» | decl «AgentStatus» |
| «ctx.approval» | «dsh-user-approval» | «request()», «effectivePolicy()», «setPolicy()»; waterfall «approval/request» | «super(ctx,'approval')» |
| «ctx.userQuestions» | «dsh-user-questions» | «ask()/askTimed()»; waterfall «user-questions/request» | «super(ctx,'userQuestions')» |
| «ctx.webServer» | «dsh-host-webserver» | «register({kind:'exact'|'prefix',path,handler})→disposer», «registerUpgrade», «registerFallback», «getOrigin()», «host/port/protocol», «collectIndexInjections()» | «super(ctx,'webServer')» |
| «ctx.jobs» | «dsh-jobs» | «list(owner?)» → «{id, kind, owner, status: running|stopping|completed|killed|failed}» | «super(ctx,'jobs')» |
| «ctx.sessionTitle» | «dsh-session-title» | «get(session)» → «{ title, source } | undefined», «rename()» | «super(ctx,'sessionTitle')» |
| «ctx.sessionProjections» | «dsh-session-projection» | «register(def)», «stateOf(session,key)», «snapshot(session,keys)», «onChanged()» | «super(ctx,'sessionProjections')» |
| «ctx.tokenMeter» | «dsh-token-meter» | «measure(session)», «estimateMessage()» (обычно достаточно проекций) | «super(ctx,'tokenMeter')» |
| «ctx.connection» | «dsh-client-connection» | «authenticatedUrl(baseUrl)» → URL c «?token=» (только для открытия GUI) | «super(ctx,'connection')» |

Опциональные сервисы брать через «ctx.get('jobs')» и т.п. — как notch («board.ts:374», «board.ts:437»).
Это правильный способ: при отсутствии сервиса фича деградирует, а не падает загрузка плагина.

### События host-уровня (подписка ctx.on(name, listener))

| Событие | Сигнатура | Смысл |
|---|---|---|
| «session/created», «session/disposed» | «(session)» | появилась/убрана живая сессия |
| «session/event» | «(session, event)» | **главный поток**: каждое принятое событие лога |
| «agent/status» | «({ agent, status })», status ∈ «'idle'|'running'» | единственный официальный «busy» |
| «agent/error» | «({ agent, turn, step, error })» | живая ошибка шага |
| «agent/created», «agent/disposed» | «({ agent })» | жизненный цикл агента |
| «agent/assistant-stream» | «({ agent, frame })» | стрим токенов (для анимации «печатает») |
| «agent/inbox/inserted|claimed|discarded|spliced» | «({...})» | очередь ввода |
| «approval/request» | waterfall «(request, next)» → «ApprovalOutcome» | **точка ответа на approval** |
| «user-questions/request» | waterfall «(request, next)» → «{ answers }» | **точка ответа на вопрос** |
| «workspace/session-activity», «workspace/session-stop» | waterfall | Activity/stop от Workspace (kind: turn|job|subagent|schedule) |

### Словарь событий сессии (лог)

Полный «SessionEventMap» вытащен из «dsh-api-session-controller/lib/typert.host.js». Нужные нам:

~~~ts
'turn/start': { turn: number }
'turn/end':   { turn: number; reason: TurnEndReason }
'step/start': { turn: number; step: number }
'step/end':   { turn: number; step: number }
'user/message': UserMessage                      // source.kind: 'user' | ...
'assistant/message': { turn; step; message; stream; usage?: TokenUsage; interrupted?: true }
'assistant/attempt': { turn; step; stream }      // неудачная попытка, в историю не идёт
'tool/call':   { turn; step; callId; name: string; arguments: string }
'tool/result': { turn; step; message: ToolResultMessage; error?; meta? }
'approval/asked':   { id; toolName; callId?; reason? }     // log-only аудит
'approval/decided': { id; outcome: ApprovalOutcome }       // log-only аудит
'approval/policy':  { policy: 'ask' | 'never'; source? }
'model/selection': ModelSelection                          // { provider, model, reasoningEffort? }
'request/header': { header: EpochHeader; reason: 'initial'|'resume'|'change'|'series' }
'session/title': SessionTitleEventData
'plan/mode': { active: boolean }
'goal/change', 'permission/preset', 'sandbox/mode', 'working-directory/change', 'compaction/*'
~~~

«TurnEndReasonMap» (точно):

~~~ts
completed:     { kind: 'completed' }
aborted:       { kind: 'aborted'; reason: TurnEndCancelCause }
blocked:       { kind: 'blocked' }
error:         { kind: 'error'; error: LlmFailure }
'max-tokens':  { kind: 'max-tokens' }
interrupted:   { kind: 'interrupted' }
forked:        { kind: 'forked' }          // только seed/fork, живой turn так не кончается
~~~

### Usage

«ctx.sessionProjections.stateOf(session, 'tokenUsage')» → «TokenUsageProjection»:

~~~ts
{ uncachedInputTokens: number; outputTokens: number; cacheReadTokens: number; cacheWriteTokens: number }
~~~

Сырой «TokenUsage» в «assistant/message.usage»: «inputTokens, outputTokens, totalTokens?,
cacheReadTokens?, cacheWriteTokens?, reasoningTokens?».

Давление на контекст: «stateOf(session,'contextPressure')» → «{ pressureTokens?, projectedTokens?, contextWindow? }»,
состав контекста: «contextBreakdown» → «{ systemTokens, toolsTokens, messageTokens }»,
тайминги/шаги: «stateOf(session,'sessionStats')» → «{ turns, steps, llmMs, toolMs, ttftMs, ttftSteps, decodeMs, decodeTokens }».

**Денег (cost) в ядре нет.** Слово «pricing» в «dsh-token-meter» / «dsh-llm» означает цену *токенов
изображений*, не валюту. Отдельного сервиса «cost/price» в 0.2.1-rc.3 нет; баланс аккаунта доступен только
на клиенте («ctx.remote.account.getBalance()» — так делает «dsh-plugin-balance-badge»).

### Проекции: что вообще читается

«SessionProjectionMap» (клиент-видимые): «inbox, workingDirectory, agentPreset, title, todos,
sessionListMetadata, imageLimits, modelSelection, permissions, subagentCatalog, subagentTiming, subagent,
tokenUsage, contextPressure, contextBreakdown, agentTeam, userQuestions, goal, plan».
Плюс host-only ключи, доступные через «stateOf()»: «sessionStats», «turnOutline», «titleInput», «turnBoundary».
«modelSelection» → «{ lastUsed: {provider,model,reasoningEffort?} | null, next: ... }» — отсюда «model» в поповере.

### Что в установленной версии объявлено устаревшим

«dsh-session/README.md»: «session.seq reads the current log length … eventAt(), snapshotEvents(), and
ownEvents() are deprecated: existing logic may remain unmigrated for now, but new production calls are
prohibited». Для нового плагина: «ctx.on('session/event')» + собственная проекция/инкрементальный fold,
а не «snapshotEvents()».

---

## (c) Рекомендуемый протокол DSH Bar

### Транспорт

**Loopback HTTP/1.1 + JSON, Bearer token из runtime.json, плюс SSE для push.** Ровно как у notch: уже
проверено в бою, не требует ни сокетов, ни framing'а, ни macOS-специфики. Нативный клиент — «URLSession»
(keep-alive сам), «URLSession.bytes(for:)» для SSE, если понадобится.

Почему не unix-сокет: у «ctx.webServer» уже есть роутинг, loopback-bind, gzip и жизнь вместе с Host;
сокет пришлось бы поднимать отдельно и объяснять Electron-шеллу.
Почему не только SSE: меню-бар просыпается по клику и должен получить состояние немедленно; поллинг
500–800 мс с дешёвым снапшотом проще и устойчивее. SSE держим как опцию (push для анимации).

### Формат сообщений

Один документ состояния («state»), а не набор ресурсов. Экшены — отдельные POST'ы с идемпотентным телом.

| Метод/путь | Аутентификация | Назначение |
|---|---|---|
| «GET /dsh-bar/status» | Bearer (нативный) | полный снапшот; одновременно «hello» — в ответе «serverId» |
| «GET /dsh-bar/events» | Bearer | SSE-поток тех же снапшотов («data: {...}») |
| «GET /dsh-bar/health» | Bearer | «{ok,pid,uptime,schemaVersion}» без состояния сессий |
| «POST /dsh-bar/focus» | Bearer | «{sessionId}» → «показать сессию в GUI» (см. (d)) |
| «POST /dsh-bar/approve» | Bearer | «{id, outcome: 'allowed-once'|'rejected'}» |
| «POST /dsh-bar/answer» | Bearer | «{id, answers:[{id,selected[],custom?}]}» |
| «POST /dsh-bar/seen» | Bearer | «{sessionId}» или «{all:true}» (M3) |
| «GET /dsh-bar/pending-focus» | same-origin/bridge trust, **без токена** | для клиентской половины в GUI |
| «POST /dsh-bar/client-state» | same-origin/bridge trust, без токена | (M3) heartbeat: активная сессия, фокус окна |
| «POST /dsh-bar/stop» | Bearer | (M3) «{sessionId}» → «agent.cancel({kind:'user'},{keepInbox:true})» |

Ошибки: «403 {ok:false,error:'forbidden'}» на неверный токен, «404 {ok:false,error:'not pending'}» на ответ
по уже снятому approval/вопросу (норма при гонке с GUI), «400» на битое тело (лимит тела 64 КиБ).

### Схема документа состояния

~~~json
{
  "schemaVersion": 1,
  "serverId": "9e0f...",
  "revision": 128,
  "generatedAt": 1761612345678,
  "origin": "http://127.0.0.1:49399",
  "app": { "bundleId": "com.deepseek.dsh", "profile": "desktop" },
  "active": {
    "sessionId": "01J...",
    "title": "Refactor the parser",
    "state": "tool",
    "detail": "bash · npm test",
    "child": false,
    "busy": true,
    "unread": false,
    "model": "deepseek-flash",
    "tokens": 18920,
    "usage": { "uncachedInputTokens": 4000, "outputTokens": 900,
               "cacheReadTokens": 14000, "cacheWriteTokens": 0 },
    "context": { "pressureTokens": 21000, "projectedTokens": 22500, "contextWindow": 128000 },
    "startedAt": 1761612300000
  },
  "counts": { "busy": 1, "waiting": 0, "unread": 0, "failed": 0 },
  "rows": [ { "id": "...", "title": "...", "state": "tool", "child": false,
              "busy": true, "unread": false, "detail": "bash · npm test",
              "model": "deepseek-flash", "tokens": 18920,
              "lastTurn": { "at": 1761610000000, "kind": "completed", "failed": false },
              "approval": { "id": "u-1", "toolName": "bash", "reason": "write src/parser.ts" },
              "ask": { "id": "q-1", "questions": [ ] } } ],
  "approvals": [ { "id": "u-1", "sessionId": "...", "title": "...", "toolName": "bash", "reason": "..." } ],
  "questions": [ { "id": "q-1", "sessionId": "...", "questions": [ ] } ]
}
~~~

Правила:

- «state» строки: приоритет «approval» (есть удержанный approval или открытый вопрос) → «error» (последний
  «turn/end.reason.kind ∈ {error,blocked,max-tokens}» **или** живой «agent/error») → «tool» (есть «tool/call»
  без парного «tool/result» по «callId» при «agent.status==='running'») → «thinking» («running») → «done»
  («idle» + последний turn «completed» + unread) → «idle».
- «cost» из «BarSnapshot» в M2 не заполняем (в ядре нет цен): «—»/токены. Позже — таблица цен по модели
  на стороне натива либо баланс через клиентскую половину.
- «unread» — не host-состояние: либо «seen.json» плагина (как в notch), либо (M3) heartbeat из GUI.
- «rows» сортируем: есть действие → busy → unread → свежесть «lastTurn.at».

### runtime.json для DSH Bar

Файл: «$DSH_HOME/dsh-bar/runtime.json» (каталог 0700, файл 0600), пишется плагином при каждой загрузке.

~~~json
{
  "schemaVersion": 1,
  "origin": "http://127.0.0.1:49399",
  "token": "48-hex-символов",
  "pid": 8217,
  "writtenAt": 1761612345678,
  "home": "/Users/a1/.dsh",
  "profile": "desktop",
  "plugin": { "name": "dsh-bar", "version": "0.1.0" },
  "appBundleId": "com.deepseek.dsh"
}
~~~

Правила (все подтверждены кодом):

- «origin» **обязателен**: Desktop запускает Host с «--host 127.0.0.1 --port 0»
  («dsh-desktop-host/lib/index.js», «args: ['--no-open','--host','127.0.0.1','--port','0']») — порт назначает ОС,
  каждый рестарт другой (в этом прогоне 49399). Хардкод 3080 недопустим (это лишь fallback web-профиля).
- «pid» — liveness-lease для натива («kill(pid,0)» + «DispatchSourceProcessSource»), а не «кто владеет».
- «token» переиспользуется между рестартами Host (иначе после рестарта старый натив получит 403).
- Натив **перечитывает** файл перед каждым запросом (notch: «reloadRuntime()» в «Client.swift:makeRequest»),
  а не кэширует на старте.
- Разрешить override пути через env «DSH_BAR_RUNTIME_FILE» (у notch «DSH_NOTCH_RUNTIME_FILE») — для тестов
  и мульти-Home.

### Авторизация

- Нативный канал: «Authorization: Bearer <token>» + обязательная проверка «isLoopback». Токен — 24 случайных
  байта hex; 0600 на файл и 0700 на каталог.
- Эндпоинты для GUI-страницы («/pending-focus», «/client-state») — **без токена** (секрет не должен попадать
  в JS страницы), но с проверкой same-origin/bridge trust: loopback + («Origin» совпадает с «Host» **или**
  «Origin»/«sec-fetch-site» отсутствуют + «x-dsh-bar-client: 1» + «content-type: application/json»).
- CSRF: любой локальный процесс/страница может дотянуться до «127.0.0.1:<port>»; поэтому **все** действия
  (approve/answer/focus/stop) — только с Bearer. Без токена — 403 и ни строчки состояния.
- Токен и снапшоты никогда не писать в логи/presentation.jsonl (notch явно оговаривает это про runtime.json).

### Частота событий

- Внутри плагина: «notify» debounce **80 мс** на «session/event» / «agent/status» / created/disposed
  (notch: «debounce(fn, 80)»); SSE-push — на каждое изменение после debounce.
- Натив: поллинг **800 мс** + «timer.tolerance = 0.2» (notch); 400–500 мс тоже ок. Меньше 200 мс смысла нет:
  «agent/status» меняется редко, а «tool/thinking» — из событий лога.
- Снапшот дешёвый: «ctx.sessions.list()» по живым сессиям + «stateOf» по проекциям; сотни байт на сессию.
- На рестарте Host «serverId» меняется → натив сбрасывает кэш и перечитывает runtime.json (новый порт!).

---

## (d) Как открыть/активировать сессию в GUI

Проверено: **deep-link'а по URL в GUI нет** (никакого «?session=»/hash-роутинга в клиенте нет; выбор сессии —
только in-memory «uiWorkspace.openSession(sessionId)», «dsh-client-ui-workspace/lib/client.js:1471»).
Значит нужны два шага: разбудить окно DSH и попросить клиентскую половину открыть сессию.

1. **Разбудить окно (натив):** «NSRunningApplication.runningApplications(withBundleIdentifier:
   "com.deepseek.dsh")» (CFBundleIdentifier подтверждён), затем «activate(options: [.activateIgnoringOtherApps])»;
   если не запущено — «NSWorkspace.shared.openApplication» / «open -b com.deepseek.dsh». Fallback на старый
   шелл «local.dsh.desktop» (notch держит оба).
2. **Попросить GUI открыть сессию:** «POST /dsh-bar/focus» «{sessionId}» (Bearer) → плагин запоминает wish
   «{sessionId, at}» (TTL 60 с, как «board.peekFocus» в notch). Клиентская половина плагина поллит
   «GET /dsh-bar/pending-focus» каждые ~400 мс; **первый ответ только «взводит»** (не дёргает сессию),
   дальше при «at > lastAt» вызывает «ctx.uiWorkspace.openSession(sessionId)» и «window.focus()».
3. **Браузерный (web) профиль:** если Desktop не запущен, а DSH открыт в браузере — плагин может вернуть
   «ctx.connection.authenticatedUrl(ctx.webServer.getOrigin())» (URL c «?token=») на «GET /dsh-bar/url»
   (только с Bearer!); натив открывает его в браузере, дальше ту же сессию откроет клиентская половина
   по «pending-focus». Токен этого URL — секрет, наружу отдавать только нативному клиенту.

Клиентская половина в 0.2.1-rc.3 делается **без сборки**: «package.json → dsh.client {platform:'web',
inject:[...]}» + «./client» export — обычный browser-артефакт с «window.__ModuleLoader__.load({ id, factory })»,
где factory возвращает «{ inject: [...], apply(ctx) {} }». Ровно так устроен работающий
«~/dsh-plugins/dsh-plugin-balance-badge/client.js» (этот же DSH 0.2.x, установлен в desktop-профиль).
Инжекты для open-session: «@deepseek-ai/dsh-client-ui-workspace», «@deepseek-ai/dsh-client-ui-session»
(и «@deepseek-ai/dsh-api-session-controller», если нужен список сессий).

---

## (e) Риски и неизвестные

1. **Версия.** dsh-notch / dsh-notch-focus заявляют «>=0.2.0-rc.1 <0.2.1», а стоит «0.2.1-rc.3». Копировать
   код notch вслепую нельзя — сверяться с этим отчётом и «typert.host.js». Deprecated-ридеры
   («snapshotEvents») в следующей версии могут исчезнуть → сразу строить на «ctx.on('session/event')» и проекциях.
2. **«ctx.sessions.list()» = только живые (загруженные) сессии.** Сессия, которую не открывали в этом прогоне
   Host, в списке отсутствует. Для меню-бара это ок (показываем активность), но «показать все сессии»
   потребует «dsh-api-session-controller» (Remote «list») или workspace-слой.
3. **Desktop-профиль управляется приложением.** «~/.dsh/profiles/desktop/package.json» пишется plugin-manager'ом;
   руками «cordis.patch.yml» не правим. Установка — через in-app Plugins page (или CLI с тем же «DSH_HOME»),
   затем перезагрузка плагина/страницы. Для dev удобно «link:/Users/a1/dsh-plugins/dsh-bar», как у dsh-doc-reader.
4. **Порт случайный** («--port 0»): runtime.json переписывается при каждом старте Host; натив обязан
   перечитывать файл и не кэшировать origin. Тест «порт 3080» будет ложноположительным.
5. **Свой транспорт — своя авторизация.** Наши роуты живут вне «/api» connection-gateway, поэтому её cookie
   нас не защищает; без Bearer любой локальный процесс сможет approve'ить. 401 на «/» и «/api» без токена — факт.
6. **Электронный бридж «dsh-app://app».** Страница Desktop грузится не по «http://127.0.0.1»: всё, что не
   «/», «/index.html», «/assets/*», уходит в «forwardWebRequest» в Host с **удалёнными**
   «host/origin/cookie/sec-fetch-site» и подставленным host-cookie. Отсюда: «isLoopback + Origin===Host»
   **не сработает** для клиентской половины; нужен fallback как в «http.ts:sidebarTrusted». Это главная
   ловушка при копировании проверок.
7. **Approvals шумят.** «approval/request» приходит и на sandbox-эскалации фоновых субагентов — именно поэтому
   notch отключил перехват. Нужен фильтр (root-сессии/foreground, dedupe по «toolName+sessionId») либо
   сознательно не трогать approvals в M2.
8. **В текущем профиле approvals не приходят вообще:** «permission/presets» в
   «~/.dsh/profiles/desktop/cordis.patch.yml» задаёт «defaultPreset: danger-full-access» с «approval: never» →
   «ApprovalService.decide()» сразу отдаёт «'rejected'», не спрашивая answerers. Проверять approval-поверхность
   надо на пресетах «read-only» / «workspace-write».
9. **Ответ после abort'а.** Approval/question может быть снят сигналом (turn отменён/сессия закрыта): ответ из
   бара обязан стать no-op (404), иначе повиснет promise/UI. В notch это делает «pending.delete(id)» в
   «signal.addEventListener('abort', ...)».
10. **Несколько Host'ов/Home.** desktop и web профили могут работать одновременно и писать разные runtime.json;
    натив должен быть привязан к одному файлу («DSH_BAR_RUNTIME_FILE»), иначе будет «переключаться» между Host'ами.
11. **Жизненный цикл натива.** Смерть Host ≠ ошибка HTTP: только pid-мониторинг (notch «HostLifetime»);
    HTTP-таймаут (8 с в «URLRequest») — не повод закрываться.
12. **Суб-агенты.** Считать «busy» по «agent.status» и объединять «origin==='subagent'» в строку корня
    («header.parentSession»), фон — через «ctx.get('jobs')?.list(agentId)» (kind «subagent», status
    «running|stopping»). Без этого счётчики будут врать (notch отдельно это чинил).
13. **Unread/read-state** в ядре нет: либо «seen.json» плагина (host), либо клиентский heartbeat. В M2 не обещать.
14. **Cost в ядре нет** (см. (b)). Либо цена на стороне натива (таблица), либо баланс через клиентскую половину,
    либо «—». Обещать точный $ из токенов нельзя — провайдерский usage и оценка различаются.
15. **SSE через Electron-бридж** («forwardWebRequest») теоретически поддержан (body стримится), но не проверен —
    неизвестный; поллинг надёжнее.
16. **Неизвестно:** точный reload-путь для host-плагина в Desktop (кнопка в Plugins page vs полный рестарт
    приложения), поведение «dsh-hmr» для нашего пакета, и как локально собранный menu-bar «.app» переживёт
    обновление DSH (не должно влиять, но приёмку на чистой машине не делали).
17. **Тестовый контур:** не устанавливать в реальный профиль без нужды; тесты поднимать с отдельным «DSH_HOME»
    (notch использует «tests/isolate-home.mjs») и фейковым runtime.json, не трогая живую сессию.

---

## (f) Минимальный API для M2

### Host-плагин «dsh-bar» (одна npm-посылка)

«package.json»:

~~~json
{
  "name": "dsh-bar",
  "type": "module",
  "main": "index.js",
  "exports": { ".": "./index.js", "./client": "./client.js", "./package.json": "./package.json" },
  "dsh": {
    "bundle": { "patch": "./cordis.patch.yml" },
    "client": { "platform": "web", "inject": [
      "@deepseek-ai/dsh-client-ui-workspace",
      "@deepseek-ai/dsh-client-ui-session"
    ] }
  },
  "engines": { "dsh": ">=0.2.1-rc.3 <0.3.0-0" }
}
~~~

«cordis.patch.yml»: «- insert: [ { id: dsh-bar, name: dsh-bar } ]» (как у dsh-doc-reader).

«index.js» (host half):

~~~js
export const name = 'dsh-bar'
export const inject = ['sessions', 'agents', 'webServer']
export const Config = Schema.object({ helperPath: Schema.string().default('') })

export function apply(ctx, config = {}) {
  // 1) runtime.json: $DSH_HOME/dsh-bar/runtime.json {schemaVersion,origin,token,pid,writtenAt,...}
  //    token: randomBytes(24).hex, переиспользовать; dir 0700 / file 0600
  // 2) ctx.webServer.register({kind:'prefix', path:'/dsh-bar', handler})
  //    Bearer для нативных ручек; bridge-trust для /pending-focus и /client-state
  // 3) инкрементальное состояние:
  //    ctx.on('session/created'|'session/disposed'|'session/event', ...)
  //    ctx.on('agent/status', ({agent,status}) => ...)
  //    ctx.on('agent/error', ({agent,turn,step,error}) => ...)
  //    debounce 80ms → notify(); snapshot() = sessions.list() + agents.get(id).status +
  //      stateOf(s,'tokenUsage'|'contextPressure'|'modelSelection'|'sessionStats')
  //      + собственный fold turn/tool/approval из session/event (ограниченный по памяти)
  // 4) approvals/questions (M3): ctx.on('approval/request', holdApproval, {prepend:true})
  //    ctx.on('user-questions/request', holdAsk, {prepend:true}) — см. board.ts:296-354
  // 5) ctx.get('jobs')?.list(agentId) для фоновых субагентов; ctx.get('sessionTitle').get(session)
  // 6) helperPath → supervise helper (pid identity + respawn limit), env DSH_BAR_RUNTIME_FILE
}
~~~

### Что должен уметь «GET /dsh-bar/status» (M2 done)

1. «schemaVersion», «serverId», «revision», «generatedAt», «origin»;
2. «active» = агрегат для иконки: «state» ∈ «idle|thinking|tool|approval|done|error», «title», «detail»,
   «model», «tokens» (из «tokenUsage»), «approvals» счётчик;
3. «counts» и «rows[]» (для поповера), сортировка как в notch;
4. устойчивость: «stateOf» может вернуть «undefined» (проекция не смонтирована) → нули;
   «ctx.get('sessionTitle')»/«jobs» отсутствуют → fallback на «session.id.slice(0,8)» и без job-атрибуции;
5. 403 без Bearer; никаких секретов и текстов сообщений в ответе (только title/toolName/reason/usage).

### Нативная сторона (M2)

- «RuntimeFileStore»: читать «runtime.json» (env override), перечитывать перед каждым запросом;
  «pid» → «DispatchSourceProcessSource(.exit)» → закрыть приложение/показать «DSH закрыт»;
- поллинг «/status» 800 мс (+tolerance), «URLRequest.timeoutInterval = 8», «Authorization: Bearer»;
- «serverId»/«revision»: при смене serverId — сброс, при равном revision — не перерисовывать;
- маппинг «state» → «BarState» («Model.swift») 1:1; «cost» в M2 = «—»;
- никаких сетевых запросов при отсутствии runtime.json (показать «DSH не найден», не спамить).

---

## Приложение: быстрые ссылки на код-референс

| Что | Где |
|---|---|
| runtime.json + token | «/tmp/dsh-notch-ref/src/store.ts» |
| сборка состояния сессий | «/tmp/dsh-notch-ref/src/board.ts» (snapshot 144-206, rowFor 380-412, holdApproval 296-318, holdAsk 320-354) |
| HTTP/SSE/auth | «/tmp/dsh-notch-ref/src/http.ts» (browserTrusted 33-46, sidebarTrusted 49-58, attachHttp 63+) |
| wiring плагина | «/tmp/dsh-notch-ref/src/dsh-notch.ts» |
| свёртка turn'ов | «/tmp/dsh-notch-ref/src/session-state.ts» |
| супервизор helper'а | «/tmp/dsh-notch-ref/desktop/notch-lifecycle.mjs» |
| нативный клиент | «/tmp/dsh-notch-ref/macos/Sources/Client.swift», «HostLifetime.swift», «RootView.swift» (poll 0.8s) |
| browser half (openSession) | «/tmp/dsh-notch-ref/src/client/index.ts», «companions/dsh-notch-focus/» |
| наш DSH, точные типы | «app.asar → dsh/node_modules/@deepseek-ai/dsh-api-session-controller/lib/typert.host.js» |
| Desktop-запуск Host | «app.asar → dsh/node_modules/@deepseek-ai/dsh-desktop-host/lib/index.js» |
| Desktop-бридж | «app.asar → lib/main.js» (protocol.handle(SCHEME), forwardWebRequest) |
| пример client-half без сборки | «~/dsh-plugins/dsh-plugin-balance-badge/client.js» |
| пример host-bundle | «~/dsh-plugins/dsh-doc-reader/{package.json,cordis.patch.yml}» |
