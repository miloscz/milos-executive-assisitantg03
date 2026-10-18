import Foundation

/// Fixed native-only actions on the official login page. Never returns DOM or field values.
public enum LoginPageScripts {
    public static let originGuard = "location.origin === 'https://uuidentity.plus4u.net' && location.pathname === '\(EndpointPolicy.loginPath)' && window === window.top"

    private static let choiceDefinition = """
    if (!(\(originGuard))) return 'denied';
    const visible = element => !!element && element.getClientRects().length > 0
      && getComputedStyle(element).visibility !== 'hidden' && getComputedStyle(element).display !== 'none';
    const first = document.querySelector('input[name="accessCode1"]');
    const second = document.querySelector('input[name="accessCode2"]');
    const accessFormVisible = visible(first) && visible(second);
    const accessLabel = /^(?:(?:Pokračovat\\s+s|Continue\\s+with|Přihlásit(?:\\s+se)?\\s+pomocí|Přihlaste\\s+se\\s+pomocí|Sign\\s+in\\s+(?:with|using))\\s*)?(?:\\+4U|Plus4U)\\s*Access$/iu;
    const samePageAction = element => {
      const target = element.getAttribute('target');
      if (target && target !== '_self') return false;
      const href = element.getAttribute('href');
      if (!href || href === '#') return true;
      try {
        const destination = new URL(href, location.href);
        return !destination.username && !destination.password
          && destination.origin === location.origin && destination.pathname === location.pathname
          && destination.search === location.search;
      } catch (_) { return false; }
    };
    const eligible = Array.from(document.querySelectorAll('button,a,[role="button"]')).filter(element =>
      (element.tagName === 'BUTTON' ? element.type === 'button' : element.tagName === 'A'
        || (['DIV', 'SPAN'].includes(element.tagName) && element.getAttribute('role') === 'button'))
      && !element.disabled && element.getAttribute('aria-disabled') !== 'true'
      && !element.closest('[inert]') && visible(element) && samePageAction(element));
    const renderedLabel = element => (element.innerText || element.textContent || '').replace(/\\s+/gu, ' ').trim();
    const choices = eligible.filter(element => accessLabel.test(renderedLabel(element)));
    """

    /// Only a fixed state crosses from WebKit into the native app.
    public static let methodProbe = choiceDefinition + """

    if (accessFormVisible) return 'formReady';
    if (choices.length > 1) return 'ambiguous';
    if (choices.length === 0 && eligible.some(element => /(?:\\+4U|Plus4U)\\s*Access/iu.test(renderedLabel(element)))) return 'unsupportedChoice';
    return choices.length === 1 ? 'choiceReady' : 'waiting';
    """

    public static let selectAccess = choiceDefinition + """

    if (accessFormVisible || choices.length !== 1) return 'notSelected';
    choices[0].click();
    return 'selected';
    """
}
