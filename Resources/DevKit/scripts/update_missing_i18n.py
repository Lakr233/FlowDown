#!/usr/bin/env python3
"""
Update missing i18n translations in Localizable.xcstrings.
This script adds missing English localizations and fixes 'new' state translations.
"""

import sys

from i18n_tools import (
    DEFAULT_KEEP_LANGUAGES,
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
        keep_languages=DEFAULT_KEEP_LANGUAGES,
    )
    save_strings(file_path, data)

    print_update_summary(file_path, counts)
