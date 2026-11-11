#!/usr/bin/env python3
"""
Update missing i18n translations in Localizable.xcstrings.
This script adds missing English localizations and fixes 'new' state translations.
"""

import sys

from i18n_tools import (
    default_file_path,
    load_strings,
    print_update_summary,
    save_strings,
    update_missing_translations,
)

WELCOME_MESSAGE = (
    "**Welcome to FlowDown🐦**, a blazing fast and smooth client app for LLMs with respect of your privacy.\n\n"
    "Use Apple Intelligence or _run local models_ on supported devices. You can also _configure cloud models_ with your own provider.\n\n"
    "💡 For more information, check out [our wiki](https://flowdown.ai/docs/).\n\n"
    "---\n**What to do next?**\n\n"
    "1. Select or _add a new model_, and **create a new conversation**.\n"
    "2. Later, you can go to **Settings** to customize your experience.\n"
    "3. For any issues, feel free to [contact us](https://discord.gg/UHKMRyJcgc).\n\n"
    "✨ **Enjoy your FlowDown experience!**"
)

# Populate this map with explicit translations when introducing new keys.
# Format: {"Key": {"zh-Hans": "示例", "es": "Ejemplo"}}
NEW_STRINGS: dict[str, dict[str, str]] = {
    "Require Confirmation": {
        "de": "Bestätigung anfordern",
        "es": "Pedir confirmación",
        "fr": "Demander une confirmation",
        "ja": "確認を求める",
        "ko": "확인 요청",
        "zh-Hans": "需要确认",
    },
    "Asks before tools use your calendar, reminders, or location, and before tools from MCP servers run.": {
        "de": "Fragt nach, bevor Tools deinen Kalender, deine Erinnerungen oder deinen Standort verwenden und bevor Tools von MCP-Servern ausgeführt werden.",
        "es": "Pregunta antes de que las herramientas usen tu calendario, tus recordatorios o tu ubicación, y antes de ejecutar herramientas de servidores MCP.",
        "fr": "Demande votre accord avant que des outils utilisent votre calendrier, vos rappels ou votre position, et avant d’exécuter des outils de serveurs MCP.",
        "ja": "ツールがカレンダー、リマインダー、位置情報を使う前と、MCP サーバーのツールを実行する前に確認します。",
        "ko": "도구가 캘린더, 미리 알림 또는 위치를 사용하기 전과 MCP 서버의 도구를 실행하기 전에 확인합니다.",
        "zh-Hans": "在工具使用你的日历、提醒事项或位置前，以及运行 MCP 服务器的工具前先向你确认。",
    },
    "Authorization": {
        "de": "Autorisierung",
        "es": "Autorización",
        "fr": "Autorisation",
        "ja": "許可",
        "ko": "권한",
        "zh-Hans": "授权",
    },
    "When this is off, tools run without asking, including ones that change your calendar or reminders. Web search, reading web pages, and memory never ask.": {
        "de": "Wenn diese Option deaktiviert ist, werden Tools ohne Nachfrage ausgeführt, auch solche, die deinen Kalender oder deine Erinnerungen ändern. Websuche, das Lesen von Webseiten und die Gedächtnisfunktion fragen nie nach.",
        "es": "Si se desactiva, las herramientas se ejecutan sin preguntar, incluidas las que modifican tu calendario o tus recordatorios. La búsqueda web, la lectura de páginas web y la memoria nunca piden confirmación.",
        "fr": "Si cette option est désactivée, les outils s’exécutent sans confirmation, y compris ceux qui modifient votre calendrier ou vos rappels. La recherche web, la lecture de pages web et la mémoire ne demandent jamais de confirmation.",
        "ja": "オフにすると、カレンダーやリマインダーを変更するツールも確認なしで実行されます。ウェブ検索、ウェブページの読み取り、メモリーは確認しません。",
        "ko": "끄면 캘린더나 미리 알림을 변경하는 도구도 묻지 않고 실행됩니다. 웹 검색, 웹 페이지 읽기, 메모리는 확인하지 않습니다.",
        "zh-Hans": "关闭后，工具会直接运行，包括会更改日历或提醒事项的工具。网页搜索、网页读取和记忆从不需要确认。",
    },
    "Allow": {
        "de": "Erlauben",
        "es": "Permitir",
        "fr": "Autoriser",
        "ja": "許可",
        "ko": "허용",
        "zh-Hans": "允许",
    },
    "Don’t Allow": {
        "de": "Nicht erlauben",
        "es": "No permitir",
        "fr": "Refuser",
        "ja": "許可しない",
        "ko": "허용 안 함",
        "zh-Hans": "不允许",
    },
    "Show Thinking and Tool Calls": {
        "de": "Denkprozess und Tool-Calls anzeigen",
        "es": "Mostrar razonamiento y llamadas de herramienta",
        "fr": "Afficher la réflexion et les appels d’outil",
        "ja": "思考過程とツールコールを表示",
        "ko": "생각 과정과 도구 호출 표시",
        "zh-Hans": "显示思考过程和工具调用",
    },
    "Show the model's thinking and each tool call as text in the chat while it replies. Trace is still available.": {
        "de": "Zeigt den Denkprozess des Modells und jeden Tool-Call während der Antwort als Text im Chat an. Der Ablauf bleibt weiterhin verfügbar.",
        "es": "Muestra como texto en el chat el razonamiento del modelo y cada llamada de herramienta mientras responde. Proceso sigue disponible.",
        "fr": "Affiche en texte dans la conversation la réflexion du modèle et chaque appel d’outil pendant la réponse. Le Déroulement reste accessible.",
        "ja": "応答中、モデルの思考過程と各ツールコールを会話内にテキストで表示します。トレースも引き続き開けます。",
        "ko": "응답하는 동안 모델의 생각 과정과 각 도구 호출을 대화에 텍스트로 표시합니다. 실행 기록도 그대로 열 수 있습니다.",
        "zh-Hans": "回复时直接在对话里用文字显示模型的思考过程和每次工具调用。过程记录照常可以打开。",
    },
    "Tool call denied.": {
        "de": "Tool-Call abgelehnt.",
        "es": "Llamada de herramienta denegada.",
        "fr": "Appel d’outil refusé.",
        "ja": "ツールコールを拒否しました。",
        "ko": "도구 호출을 거부했습니다.",
        "zh-Hans": "已拒绝此次工具调用。",
    },
    "Stopped after %lld rounds of tool calls.": {
        "de": "Nach %lld Runden von Tool-Calls angehalten.",
        "es": "Se detuvo tras %lld rondas de llamadas de herramienta.",
        "fr": "Arrêté après %lld séries d’appels d’outils.",
        "ja": "ツールコールを %lld 回繰り返したため停止しました。",
        "ko": "도구 호출을 %lld회 반복하여 중지했습니다.",
        "zh-Hans": "工具调用达 %lld 轮后已停止。",
    },
    "The MCP server reported an error.": {
        "de": "Der MCP-Server hat einen Fehler gemeldet.",
        "es": "El servidor MCP informó de un error.",
        "fr": "Le serveur MCP a signalé une erreur.",
        "ja": "MCP サーバーがエラーを返しました。",
        "ko": "MCP 서버에서 오류를 보고했습니다.",
        "zh-Hans": "MCP 服务器报告了错误。",
    },
    "Send": {
        "de": "Senden",
        "es": "Enviar",
        "fr": "Envoyer",
        "ja": "送信",
        "ko": "보내기",
        "zh-Hans": "发送",
    },
    "Executing tool…": {
        "de": "Werkzeug wird ausgeführt…",
        "es": "Ejecutando herramienta…",
        "fr": "Exécution de l’outil…",
        "ja": "ツールを実行中…",
        "ko": "도구 실행 중…",
        "zh-Hans": "正在执行工具…",
    },
    "Executing %lld tools…": {
        "de": "%lld Tools werden ausgeführt…",
        "es": "Ejecutando %lld herramientas…",
        "fr": "Exécution de %lld outils…",
        "ja": "%lld個のツールを実行中…",
        "ko": "도구 %lld개 실행 중…",
        "zh-Hans": "正在执行 %lld 个工具…",
    },
    "Called 1 tool": {
        "de": "1 Tool aufgerufen",
        "es": "Usó 1 herramienta",
        "fr": "A appelé 1 outil",
        "ja": "1個のツールを呼び出しました",
        "ko": "도구 1개 호출함",
        "zh-Hans": "调用了 1 个工具",
    },
    "Called %lld tools": {
        "de": "%lld Tools aufgerufen",
        "es": "Usó %lld herramientas",
        "fr": "A appelé %lld outils",
        "ja": "%lld個のツールを呼び出しました",
        "ko": "도구 %lld개 호출함",
        "zh-Hans": "调用了 %lld 个工具",
    },
    "Thought for 1 second": {
        "de": "1 Sekunde nachgedacht",
        "es": "Pensó durante 1 segundo",
        "fr": "A réfléchi 1 seconde",
        "ja": "1秒間思考しました",
        "ko": "1초 동안 생각함",
        "zh-Hans": "思考了 1 秒",
    },
    "Thought for 1 second and called 1 tool": {
        "de": "1 Sekunde nachgedacht und 1 Tool aufgerufen",
        "es": "Pensó durante 1 segundo y usó 1 herramienta",
        "fr": "A réfléchi 1 seconde et appelé 1 outil",
        "ja": "1秒間思考し、1個のツールを呼び出しました",
        "ko": "1초 동안 생각하고 도구 1개를 호출함",
        "zh-Hans": "思考了 1 秒，调用了 1 次工具",
    },
    "Thought for 1 second and called %lld tools": {
        "de": "1 Sekunde nachgedacht und %lld Tools aufgerufen",
        "es": "Pensó durante 1 segundo y usó %lld herramientas",
        "fr": "A réfléchi 1 seconde et appelé %lld outils",
        "ja": "1秒間思考し、%lld個のツールを呼び出しました",
        "ko": "1초 동안 생각하고 도구 %lld개를 호출함",
        "zh-Hans": "思考了 1 秒，调用了 %lld 次工具",
    },
    "Thought for %lld seconds and called 1 tool": {
        "de": "%lld Sekunden nachgedacht und 1 Tool aufgerufen",
        "es": "Pensó durante %lld segundos y usó 1 herramienta",
        "fr": "A réfléchi %lld secondes et appelé 1 outil",
        "ja": "%lld秒間思考し、1個のツールを呼び出しました",
        "ko": "%lld초 동안 생각하고 도구 1개를 호출함",
        "zh-Hans": "思考了 %lld 秒，调用了 1 次工具",
    },
    "Thought for %lld seconds and called %lld tools": {
        "de": "%lld Sekunden nachgedacht und %lld Tools aufgerufen",
        "es": "Pensó durante %lld segundos y usó %lld herramientas",
        "fr": "A réfléchi %lld secondes et appelé %lld outils",
        "ja": "%lld秒間思考し、%lld個のツールを呼び出しました",
        "ko": "%lld초 동안 생각하고 도구 %lld개를 호출함",
        "zh-Hans": "思考了 %lld 秒，调用了 %lld 次工具",
    },
    "Trace": {
        "de": "Ablauf",
        "es": "Proceso",
        "fr": "Déroulement",
        "ja": "トレース",
        "ko": "실행 기록",
        "zh-Hans": "过程记录",
    },
    "Thoughts": {
        "de": "Gedanken",
        "es": "Razonamiento",
        "fr": "Réflexions",
        "ja": "思考内容",
        "ko": "생각 내용",
        "zh-Hans": "思考内容",
    },
    "View Thoughts": {
        "de": "Gedanken anzeigen",
        "es": "Ver razonamiento",
        "fr": "Afficher les réflexions",
        "ja": "思考内容を表示",
        "ko": "생각 내용 보기",
        "zh-Hans": "查看思考内容",
    },
    "Look Up": {
        "de": "Nachschlagen",
        "es": "Consultar",
        "fr": "Rechercher",
        "ja": "調べる",
        "ko": "찾아보기",
        "zh-Hans": "查询",
    },
    "Share…": {
        "de": "Teilen…",
        "es": "Compartir…",
        "fr": "Partager…",
        "ja": "共有…",
        "ko": "공유…",
        "zh-Hans": "分享…",
    },
    "Thinking…": {
        "de": "Denkt nach…",
        "es": "Pensando…",
        "fr": "Réflexion…",
        "ja": "思考中…",
        "ko": "생각 중…",
        "zh-Hans": "正在思考…",
    },
    "Authorization (Optional)": {
        "de": "Autorisierung (optional)",
        "es": "Autorización (opcional)",
        "fr": "Autorisation (facultatif)",
        "ja": "Authorization（任意）",
        "ko": "Authorization(선택 사항)",
        "zh-Hans": "Authorization（可选）",
    },
    "Bearer token": {
        "de": "Bearer-Token",
        "es": "Token Bearer",
        "fr": "Jeton Bearer",
        "ja": "Bearer トークン",
        "ko": "Bearer 토큰",
        "zh-Hans": "Bearer 令牌",
    },
    "Delete All": {
        "de": "Alle löschen",
        "es": "Eliminar todo",
        "fr": "Tout supprimer",
        "ja": "すべて削除",
        "ko": "모두 삭제",
        "zh-Hans": "全部删除",
    },
    "Edit Authorization (Optional)": {
        "de": "Autorisierung bearbeiten (optional)",
        "es": "Editar autorización (opcional)",
        "fr": "Modifier l’autorisation (facultatif)",
        "ja": "Authorization を編集（任意）",
        "ko": "Authorization 편집(선택 사항)",
        "zh-Hans": "编辑 Authorization（可选）",
    },
    "This token is sent as a Bearer credential in the Authorization header.": {
        "de": "Dieses Token wird als Bearer-Zugangsdaten im Authorization-Header gesendet.",
        "es": "Este token se envía como credencial Bearer en el encabezado Authorization.",
        "fr": "Ce jeton est envoyé comme identifiant Bearer dans l’en-tête Authorization.",
        "ja": "このトークンは Authorization ヘッダーの Bearer 認証情報として送信されます。",
        "ko": "이 토큰은 Authorization 헤더의 Bearer 인증 정보로 전송됩니다.",
        "zh-Hans": "此令牌会作为 Bearer 凭据通过 Authorization 标头发送。",
    },
    "This token is sent as a Bearer credential in the Authorization header. Leave it blank if the endpoint does not require authentication.": {
        "de": "Dieses Token wird als Bearer-Zugangsdaten im Authorization-Header gesendet. Lassen Sie es leer, wenn der Endpunkt keine Authentifizierung erfordert.",
        "es": "Este token se envía como credencial Bearer en el encabezado Authorization. Déjalo en blanco si el endpoint no requiere autenticación.",
        "fr": "Ce jeton est envoyé comme identifiant Bearer dans l’en-tête Authorization. Laissez-le vide si le point de terminaison ne nécessite pas d’authentification.",
        "ja": "このトークンは Authorization ヘッダーの Bearer 認証情報として送信されます。エンドポイントで認証が不要な場合は空欄にしてください。",
        "ko": "이 토큰은 Authorization 헤더의 Bearer 인증 정보로 전송됩니다. 엔드포인트에 인증이 필요하지 않으면 비워 두세요.",
        "zh-Hans": "此令牌会作为 Bearer 凭据通过 Authorization 标头发送。如果端点不需要身份验证，请留空。",
    },
    "Would you like to apply the new Authorization token to all models with the same inference endpoint and current token?": {
        "de": "Möchten Sie das neue Autorisierungs-Token auf alle Modelle mit demselben Inferenzendpunkt und dem aktuellen Token anwenden?",
        "es": "¿Quieres aplicar el nuevo token de autorización a todos los modelos con el mismo endpoint de inferencia y el token actual?",
        "fr": "Voulez-vous appliquer le nouveau jeton d’autorisation à tous les modèles ayant le même point de terminaison d’inférence et le jeton actuel ?",
        "ja": "同じ推論エンドポイントと現在のトークンを使用するすべてのモデルに、新しい Authorization トークンを適用しますか？",
        "ko": "동일한 추론 엔드포인트와 현재 토큰을 사용하는 모든 모델에 새 Authorization 토큰을 적용할까요?",
        "zh-Hans": "是否将新的 Authorization 令牌应用到推理端点和当前令牌均相同的所有模型？",
    },
    "Start Date": {
        "de": "Startdatum",
        "es": "Fecha de inicio",
        "fr": "Date de début",
        "ja": "開始日",
        "ko": "시작일",
        "zh-Hans": "开始日期",
    },
    "End Date": {
        "de": "Enddatum",
        "es": "Fecha de fin",
        "fr": "Date de fin",
        "ja": "終了日",
        "ko": "종료일",
        "zh-Hans": "结束日期",
    },
    "Include All-Day Events": {
        "de": "Ganztägige Ereignisse einbeziehen",
        "es": "Incluir eventos de todo el día",
        "fr": "Inclure les événements sur la journée",
        "ja": "終日イベントを含める",
        "ko": "종일 이벤트 포함",
        "zh-Hans": "包括全天事件",
    },
    "Event Data": {
        "de": "Ereignisdaten",
        "es": "Datos del evento",
        "fr": "Données de l’événement",
        "ja": "イベントデータ",
        "ko": "이벤트 데이터",
        "zh-Hans": "事件数据",
    },
    "Locale": {
        "de": "Gebietsschema",
        "es": "Configuración regional",
        "fr": "Paramètres régionaux",
        "ja": "ロケール",
        "ko": "로케일",
        "zh-Hans": "区域设置",
    },
    "Notes": {
        "de": "Notizen",
        "es": "Notas",
        "fr": "Notes",
        "ja": "メモ",
        "ko": "메모",
        "zh-Hans": "备注",
    },
    "Due Date": {
        "de": "Fälligkeitsdatum",
        "es": "Fecha de vencimiento",
        "fr": "Date d’échéance",
        "ja": "期限",
        "ko": "기한",
        "zh-Hans": "到期时间",
    },
    "Priority": {
        "de": "Priorität",
        "es": "Prioridad",
        "fr": "Priorité",
        "ja": "優先度",
        "ko": "우선순위",
        "zh-Hans": "优先级",
    },
    "List": {
        "de": "Liste",
        "es": "Lista",
        "fr": "Liste",
        "ja": "リスト",
        "ko": "목록",
        "zh-Hans": "列表",
    },
    "Reminder ID": {
        "de": "Erinnerungs-ID",
        "es": "ID del recordatorio",
        "fr": "ID du rappel",
        "ja": "リマインダー ID",
        "ko": "미리 알림 ID",
        "zh-Hans": "提醒事项 ID",
    },
    "Status": {
        "de": "Status",
        "es": "Estado",
        "fr": "Statut",
        "ja": "ステータス",
        "ko": "상태",
        "zh-Hans": "状态",
    },
    "Earliest Due Date": {
        "de": "Fällig ab",
        "es": "Vence desde",
        "fr": "Échéance à partir du",
        "ja": "最も早い期限",
        "ko": "가장 이른 기한",
        "zh-Hans": "最早到期时间",
    },
    "Latest Due Date": {
        "de": "Fällig bis",
        "es": "Vence hasta",
        "fr": "Échéance jusqu’au",
        "ja": "最も遅い期限",
        "ko": "가장 늦은 기한",
        "zh-Hans": "最晚到期时间",
    },
    "Earliest Alert": {
        "de": "Hinweis ab",
        "es": "Aviso desde",
        "fr": "Alerte à partir du",
        "ja": "最も早い通知",
        "ko": "가장 이른 알림",
        "zh-Hans": "最早提醒时间",
    },
    "Latest Alert": {
        "de": "Hinweis bis",
        "es": "Aviso hasta",
        "fr": "Alerte jusqu’au",
        "ja": "最も遅い通知",
        "ko": "가장 늦은 알림",
        "zh-Hans": "最晚提醒时间",
    },
    "Earliest Completion Date": {
        "de": "Erledigt ab",
        "es": "Completado desde",
        "fr": "Terminé à partir du",
        "ja": "最も早い完了日",
        "ko": "가장 이른 완료일",
        "zh-Hans": "最早完成时间",
    },
    "Latest Completion Date": {
        "de": "Erledigt bis",
        "es": "Completado hasta",
        "fr": "Terminé jusqu’au",
        "ja": "最も遅い完了日",
        "ko": "가장 늦은 완료일",
        "zh-Hans": "最晚完成时间",
    },
    "Clear Notes": {
        "de": "Notizen entfernen",
        "es": "Quitar notas",
        "fr": "Supprimer les notes",
        "ja": "メモを消去",
        "ko": "메모 지우기",
        "zh-Hans": "清除备注",
    },
    "Clear Due Date": {
        "de": "Fälligkeitsdatum entfernen",
        "es": "Quitar fecha de vencimiento",
        "fr": "Supprimer l’échéance",
        "ja": "期限を消去",
        "ko": "기한 지우기",
        "zh-Hans": "清除到期时间",
    },
    "Clear Priority": {
        "de": "Priorität entfernen",
        "es": "Quitar prioridad",
        "fr": "Supprimer la priorité",
        "ja": "優先度を消去",
        "ko": "우선순위 지우기",
        "zh-Hans": "清除优先级",
    },
    "Yes": {
        "de": "Ja",
        "es": "Sí",
        "fr": "Oui",
        "ja": "はい",
        "ko": "예",
        "zh-Hans": "是",
    },
    "No": {
        "de": "Nein",
        "es": "No",
        "fr": "Non",
        "ja": "いいえ",
        "ko": "아니요",
        "zh-Hans": "否",
    },
    WELCOME_MESSAGE: {
        "de": (
            "**Willkommen bei FlowDown🐦**, einer blitzschnellen und flüssigen Client-App für LLMs, die deine Privatsphäre respektiert.\n\n"
            "Verwende Apple Intelligence oder führe auf unterstützten Geräten _lokale Modelle_ aus. Du kannst außerdem _Cloud-Modelle_ mit deinem eigenen Anbieter konfigurieren.\n\n"
            "💡 Weitere Infos findest du in [unserem Wiki](https://flowdown.ai/docs/).\n\n"
            "---\n**Was als Nächstes?**\n\n"
            "1. Wähle oder _füge ein neues Modell hinzu_ und **erstelle eine neue Unterhaltung**.\n"
            "2. Später kannst du in den **Einstellungen** dein Erlebnis anpassen.\n"
            "3. Bei Fragen: [kontaktiere uns](https://discord.gg/UHKMRyJcgc).\n\n"
            "✨ **Viel Spaß mit FlowDown!**"
        ),
        "es": (
            "**Bienvenido a FlowDown🐦**, una app de cliente para LLMs rápida y fluida que respeta tu privacidad.\n\n"
            "Usa Apple Intelligence o _ejecuta modelos locales_ en dispositivos compatibles. También puedes _configurar modelos en la nube_ con tu propio proveedor.\n\n"
            "💡 Para más información, consulta [nuestra wiki](https://flowdown.ai/docs/).\n\n"
            "---\n**¿Qué hacer a continuación?**\n\n"
            "1. Selecciona o _añade un modelo nuevo_ y **crea una conversación nueva**.\n"
            "2. Luego puedes ir a **Ajustes** para personalizar tu experiencia.\n"
            "3. Si tienes alguna duda, [contáctanos](https://discord.gg/UHKMRyJcgc).\n\n"
            "✨ **¡Disfruta la experiencia FlowDown!**"
        ),
        "fr": (
            "**Bienvenue sur FlowDown🐦**, une application cliente ultra-rapide et fluide pour les LLMs, respectueuse de votre vie privée.\n\n"
            "Utilisez Apple Intelligence ou _exécutez des modèles locaux_ sur les appareils compatibles. Vous pouvez aussi _configurer des modèles cloud_ avec votre propre fournisseur.\n\n"
            "💡 Pour en savoir plus, consultez [notre wiki](https://flowdown.ai/docs/).\n\n"
            "---\n**Que faire ensuite ?**\n\n"
            "1. Sélectionnez ou _ajoutez un nouveau modèle_, puis **créez une nouvelle conversation**.\n"
            "2. Plus tard, vous pourrez aller dans **Réglages** pour personnaliser votre expérience.\n"
            "3. Pour tout problème, [contactez-nous](https://discord.gg/UHKMRyJcgc).\n\n"
            "✨ **Profitez de votre expérience FlowDown !**"
        ),
        "ja": (
            "**FlowDown🐦 へようこそ**。プライバシーを重視した高速で滑らかな LLM クライアントです。\n\n"
            "Apple Intelligence を使用するか、対応デバイス上で _ローカルモデルを実行_ できます。また、独自のプロバイダで _クラウドモデルを設定_ することもできます。\n\n"
            "💡 詳細は[ウィキ](https://flowdown.ai/docs/)をご覧ください。\n\n"
            "---\n**次にやること**\n\n"
            "1. _新しいモデルを選ぶ/追加_ して **新しい会話を作成**。\n"
            "2. あとで **設定** から体験をカスタマイズ。\n"
            "3. 問題があれば[お問い合わせ](https://discord.gg/UHKMRyJcgc)。\n\n"
            "✨ **FlowDown をお楽しみください！**"
        ),
        "ko": (
            "**FlowDown🐦에 오신 것을 환영합니다.** 빠르고 부드러운 LLM 클라이언트로 개인정보를 존중합니다.\n\n"
            "Apple Intelligence를 사용하거나 지원되는 기기에서 _로컬 모델을 실행_하세요. 자체 제공업체로 _클라우드 모델을 설정_할 수도 있습니다.\n\n"
            "💡 더 자세한 정보는 [위키](https://flowdown.ai/docs/)를 확인하세요.\n\n"
            "---\n**다음에 무엇을 할까요?**\n\n"
            "1. 모델을 선택하거나 _새 모델을 추가_하고 **새 대화를 만드세요.**\n"
            "2. 나중에 **설정**에서 경험을 맞춤화할 수 있습니다.\n"
            "3. 문제가 있으면 언제든지 [문의하기](https://discord.gg/UHKMRyJcgc)로 연락하세요.\n\n"
            "✨ **FlowDown을 마음껏 즐겨보세요!**"
        ),
        "zh-Hans": (
            "**欢迎使用 FlowDown 🐦**，一款注重隐私、极速流畅且轻量高效的 LLM 客户端。\n\n"
            "你可以使用 Apple Intelligence，或在支持的设备上 _运行本地模型_。也可以使用自己的服务提供商 _配置云端模型_。\n\n"
            "💡 更多信息，请查阅[用户手册](https://flowdown.ai/docs/)。\n\n"
            "---\n**接下来可以做些什么？**\n\n"
            "1.  _选择或添加新模型_，然后 **开始一个新对话**。\n"
            "2.  之后，你可以前往 **设置** 来自定义你的使用体验。\n"
            "3.  若有任何疑问反馈或建议，欢迎[联系我们](https://discord.gg/UHKMRyJcgc)。\n\n"
            "✨ **祝你使用愉快！**"
        ),
    },
}

if __name__ == "__main__":
    file_path = sys.argv[1] if len(sys.argv) > 1 else default_file_path()

    data = load_strings(file_path)
    counts = update_missing_translations(
        data,
        new_strings=NEW_STRINGS,
    )
    save_strings(file_path, data)

    print_update_summary(file_path, counts)
