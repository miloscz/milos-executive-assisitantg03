# Ověření přihlášení Iris Connect

Datum 18. října 2026. Cílem prvního prototypu je izolovat AC1/AC2 od agentů, ověřit přihlášení s MFA a jedno skutečné čtení. Vývoj i pilot probíhají na současném Macu. Mac mini je až následná etapa.

## Ověřené vstupy

- Zdrojový kód původní Iris používá Authorization Code s browser loginem, loopback callbackem a následným JSON voláním tokenového endpointu. AC1/AC2 ani MFA neimplementuje sám. Tokeny původní Iris jsou uložené v souboru; nová aplikace toto uložení nepřebírá.
- Veřejný OIDC discovery dokument na produkčním issueru byl načten bez přihlášení. Deklaruje Authorization Code a PKCE `S256`. Potvrdil adresy `oidc/auth`, `oidc/grantToken`, `oidc/listKeys` a `oidc/getIdentity`.
- Neautentizovaný autorizační požadavek se přesměroval na oficiální `uuIdentityManagement/login`.
- Veřejný klientský bundle login stránky verze 1.47.9 obsahuje přihlášení pomocí přístupových kódů a MFA. Formulář používá jména `accessCode1` a `accessCode2` a POST do `authAccessCodes/authenticate`. Prototyp využívá oficiální formulář a jeho obsluhu MFA, nevymýšlí vlastní challenge/polling API.
- uuKnowledgeBase neposkytla kompletní DTO a postup pro přímý credentials grant s MFA. Podpora grantu `password` v discovery není důkazem podpory druhého faktoru.

Při této kontrole nebyly zadávány nebo načítány skutečné AC1/AC2, původní tokenový soubor ani obsah Keychain uživatele. Veřejné protokolové sondy nepoužily uživatelské cookies.

## Stav ověření

| Oblast | Stav |
| --- | --- |
| Kontrola původní implementace | Dokončena. |
| Veřejné discovery, PKCE a přesměrování | Ověřeno neautentizovaným požadavkem. |
| Nativní prototyp a kontrola izolace údajů | Release aplikace sestavena a otevřena na tomto Macu. Ověřen místní ad hoc podpis s hardened runtime a bez debugger entitlementu. |
| Automatické testy protokolu | 5 testů prošlo, včetně skutečného RS256 podpisu se syntetickým klíčem. Žádné testy nečtou uživatelskou klíčenku. |
| Přihlášení skutečným účtem přes AC1/AC2 | Živě ověřeno 18. října 2026 na současném Macu. Kódy zadal uživatel v nativním okně; aplikace je doplnila a odeslala oficiálním formulářem. Agent kódy nečetl. |
| MFA | Uživatel po úspěšném přihlášení potvrdil dokončení MFA v aplikaci i v konverzaci. Jde o uživatelské potvrzení, nikoli samostatný kryptografický důkaz druhého faktoru. |
| Podpis tokenu a čtení identity | Živě ověřeno: aplikace dokončila validaci podpisu a claims a provedla úspěšné čtení `oidc/getIdentity`. Sanitizovaný stav je `verified`, bez chyb validace. Agent token nečetl. |
| Napojení na Aidu | Další implementační krok. |

## Podmínky ručního ověření

Před zadáním údajů dokončit sestavení, podpis a kontrolu kódu. Agent potom neovládá přihlašovací okna ani nesnímá jejich obsah. Uživatel vyplní oba kódy v nativním okně a dokončí MFA. Ověření se předá jen jako sanitizovaný stav podle [návodu aplikace](../apps/iris-connect/README.md).

Úspěch znamená platný podpis ID tokenu, správné claims a úspěšné čtení pevného endpointu identity. Ověření, že byl skutečně vykonán druhý faktor, se zaznamenává odděleně jako potvrzení uživatele. Zmeškaný nebo zrušený pokus nesmí vyvolat opakované automatické přihlášení.

Sestavená aplikace je v `build/Iris Connect.app`. Používá macOS file-based Keychain ACL; SDK tuto API označuje jako deprecated. Prototyp ji záměrně používá pro lokální build bez Apple Developer team podpisu a nepřechází při chybě na souborové uložení. Před distribuční verzí je nutné zvolit stabilní podpis a odpovídající Keychain strategii.

## Kompatibilita autorizovaného klienta a stránky showToken

Původní validátor vyžadoval `azp` při více hodnotách `aud`. Aktuální OpenID Connect Core 1.0 s errata 2 v oddílu 3.1.3.7 tuto povinnost nestanovuje. Opravený validátor vyžaduje očekávaný `client_id` v `aud`, povolí jen výslovně důvěryhodné další audience a případné přítomné `azp` ověří proti témuž klientovi. Chybějící `azp` není nesoulad; přítomná cizí nebo nesprávně typovaná hodnota se nadále odmítá. Podpis, issuer, nonce a časové kontroly zůstávají povinné.

Regresní testy prošly pro více důvěryhodných audience bez `azp`, správné `azp`, chybné a nesprávně typované `azp`, další neznámou audience i výslovně povolenou call audience. Release aplikace byla po této opravě znovu sestavena, podepsána a otevřena. Následný živý pokus prošel validací i čtením identity. Původní chyba byla ve validátoru prototypu; nebylo nutné získávat token z obrazovky `showToken`.

Sanitizovaný výsledek úspěšného pokusu: `tokenSignatureVerified=true`, `readProbePassed=true`, `credentialsSubmittedByApp=true`, `mfaConfirmedByUser=true`, `validationFailures=[]`. Kódy, token ani hodnoty claims nebyly agentovi předány. Výsledek dokládá funkčnost této kombinace klienta, účtu a lokálního buildu; neověřuje dosud obnovení po restartu, expiraci, napojení Aidy ani pracovní uuCommandy.

Veřejná implementace `uuIdentityManagement/showToken` byla prověřena bez cookies nebo přihlášené relace. Stránka používá komponentu `UuIdentity.ShowToken`, která volá `session.getCallToken` se scope `openid https://` a volitelným `callTokenType` podle URL parametru `tokenType`. Toto volání používá již přihlášenou relaci. Nejde o požadavek, aby uživatel předával zobrazený token agentovi.

Prototyp zatím zachovává Authorization Code a scope současné Iris. Tato oprava nemění login na získávání hodnot z obrazovky `showToken`. Vydávání call tokenů pro konkrétní schválené pracovní operace bude navazující součást proxy. Skutečné použití tokenu pro jeden pevný čtecí endpoint ověří aplikace po úspěšné validaci.

## Automatická volba Plus4U Access ve verzi 0.2.2

Nativní aplikace nyní rozpozná jednoznačné viditelné tlačítko **Pokračovat s +4U Access** nebo **Continue with +4U Access** a jednou je zvolí před doplněním kódů. Podporuje i samostatný popisek **+4U Access**. Stav volby se označí před odesláním skriptu, aby výpadek odpovědi WebKitu nemohl vyvolat druhé kliknutí. Již otevřený formulář kódů nepřepíná.

Skript běží pouze uvnitř nativního soukromého WebView na přesném originu a cestě `uuIdentityManagement/login` v hlavním dokumentu. Nečte hodnoty přihlašovacích polí do diagnostiky, nepoužívá nástroje agenta k ovládání přihlašovacího okna a nepřidává obecné vykonávání skriptů. Kódy se načtou z Keychain až po ověření správného oficiálního formuláře; nadále se odesílají nejvýše jednou. MFA, PKCE, state, nonce a validace tokenu zůstávají zachované.

Podklady byly ověřeny z veřejné stránky bez cookies a přihlášené relace. Aktuální veřejný bundle je stále verze 1.47.9; obsluha tlačítka pouze přepne na `AccessCodesForm`. Dokumentace popisuje nastavení `expandPlus4ULogin` v konfiguraci registrovaného klienta, nikoli doložený per-request parametr pro výběr Access. Konfigurace existujícího OIDC klienta se nemění. Nativní volba je lokální adaptér současného UI, nikoli garantovaný nový OIDC kontrakt.

Automatické ověření: **22 testů prošlo**, z toho 5 nových testů provádí skutečný produkční skript v JavaScriptCore nad syntetickým DOM. Pokrývají české/anglické popisky, již otevřený formulář, jiné poskytovatele, submit, skryté a zakázané prvky, nejednoznačnost, cizí origin, jinou cestu a iframe. Testy nečtou žádné skutečné přihlašovací okno ani uživatelské údaje.

Živý průchod verze 0.2.1 neprošel: zůstala nabídka Plus4U Access, nativní příznaky volby i odeslání kódů zůstaly `false` a pokus skončil chybou `loginMethod`. Úspěch proto nebyl prohlášen podle samotných syntetických testů.

Verze **0.2.2** používá vykreslený popisek (`innerText`), podporuje i označení **Plus4U Access**, známé české/anglické varianty výzvy a rozdílné mezery. Rozpozná tlačítko, odkaz nebo `DIV`/`SPAN` s rolí tlačítka. Odkaz nesmí změnit origin, cestu ani query přihlášení, obsahovat userinfo nebo otevřít jiné okno. Submit prvky zůstávají zakázané. Není doloženo, která konkrétní odlišnost způsobila neúspěch 0.2.1; přihlašovací UI uživatele agent nečetl.

Pro 0.2.2 prošlo **24 testů**, z toho 7 pro produkční skript výběru metody. Kromě původních kontrol pokrývají vykreslený text oproti skrytému textu, odkaz, roli tlačítka, cizí adresy, změnu query, userinfo a submit input. Testovací parser URL používá Foundation, aby se skutečně ověřovaly i větve práce s adresou.

**Živý průchod 0.2.2 byl úspěšně ověřen 18. října 2026 na tomto Macu.** Uživatel potvrdil: „Přihlásilo se to automaticky, já pouze potvrdil mfa.“ Sanitizovaný stav aplikace je `authenticated`, `accessMethodSelectionAttempted=true`, `accessMethodSelectedByApp=true`, `credentialsSubmittedByApp=true`, `tokenSignatureVerified=true`, `readProbePassed=true`, `validationFailures=[]`. Automatická volba Access, doplnění a odeslání kódů, validace tokenu i následné čtení identity tedy prošly. Agent nečetl přihlašovací okno, kódy ani token.

`mfaConfirmedByUser=false` v nativním záznamu znamená, že uživatel neklikl na volitelné diagnostické potvrzení v aplikaci. Dokončení MFA potvrdil v konverzaci; tento údaj se nevydává za samostatný kryptografický důkaz druhého faktoru a sanitizovaný soubor se ručně nepřepisuje. Po zahájení přihlášení nebylo nutné ručně vybírat Access na Macu.

Sanitizovaný `loginPageProbe` vrací jen pevné fáze (`notStarted`, `waiting`, `choiceReady`, `formReady`, `ambiguous`, `denied`, `unsupportedChoice`), nikdy popisek nebo obsah stránky. Volitelné tlačítko potvrzení MFA v aplikaci není podmínkou dokončení OAuth toku.

Zahájení přihlášení přes Aidu a upozornění před MFA zůstávají samostatnou dosud neimplementovanou integrací. Tento krok automatizuje volbu metody po zahájení přihlášení; neslibuje přihlášení na zamčeném Macu ani odstranění jednorázového Keychain souhlasu po změně buildu.

## Zdroje

- Původní `mcp-servers/iris-dwg-mcp/src/oidc.js` a `src/auth.js` v projektu `/Users/milosvodrazka/Personal/milos_executive_assistant`.
- [Veřejná OIDC konfigurace](https://uuidentity.plus4u.net/uu-oidc-maing02/bb977a99f4cc4c37a2afce3fd599d0a7/oidc/.well-known/openid-configuration)
- [Autentizační protokoly uuIdentity](https://uuapp.plus4u.net/uu-bookkit-maing01/ad1916b8190d46b1bd3bcde1f02a140a/book/page?code=71067309)
- [Apple Keychain Services](https://developer.apple.com/documentation/security/keychain-services)
- [OAuth pro nativní aplikace](https://www.rfc-editor.org/rfc/rfc8252.html)
- [OpenID Connect ID Token Validation](https://openid.net/specs/openid-connect-core-1_0.html#IDTokenValidation)
- [Stránka showToken](https://uuidentity.plus4u.net/uu-identitymanagement-maing01/a9b105aff2744771be4daa8361954677/showToken)
- [Veřejná implementace ShowToken](https://cdn.plus4u.net/uu-identitymanagementg01/1.0.0/uu_identitymanagementg01-core.min.js)
- [Veřejný login bundle 1.47.9](https://uuidentity.plus4u.net/uu-identitymanagement-maing01/a9b105aff2744771be4daa8361954677/public/1.47.9/login.js)
- [České popisky loginu 1.47.9](https://uuidentity.plus4u.net/uu-identitymanagement-maing01/a9b105aff2744771be4daa8361954677/public/1.47.9/chunks/index/7726-6981441b181a4cc32d0d.min.js)
- [Konfigurace přihlašovací brány OIDC klienta](https://uuapp.plus4u.net/uu-bookkit-maing01/040b09fbc5bc44189924b04f600be011/book/page?code=26386080)


## Mac mini – Iris Connect 0.4.1

18. října 2026 Miloš potvrdil úspěšné ruční přihlášení a čtení identity v nově nasazené aplikaci na Macu mini. Sanitizovaný stav z 14:55:39 Europe/Prague doložil automatickou volbu Plus4U Access, doplnění kódů aplikací, ověřený podpis tokenu, úspěšné čtení identity a žádné validační chyby. Žádný agent nečetl přihlašovací UI, AC1/AC2, token ani klíčenku. Uživatel předem potvrdil nativní import konfigurace klienta; schválená dočasná kopie zdroje byla následně odstraněna.

Pokus proběhl odemčený a z místního tlačítka. Není tím ověřené přihlášení při zamčení ani start přes Aidu/MCP. Volitelné nativní potvrzení MFA nebylo stisknuté; Miloš později v konverzaci výslovně potvrdil MFA na telefonu. Podrobnosti jsou v [provozním záznamu](mac-mini-deployment.md). Čtení pracovních seznamů má samostatné párování a pilot.
