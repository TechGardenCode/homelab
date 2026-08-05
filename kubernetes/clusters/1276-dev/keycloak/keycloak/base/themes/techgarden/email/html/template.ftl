<#--
  TechGarden branded email layout (WS-05).

  Overrides base/email/html/template.ftl. Every html/*.ftl in the base theme imports
  this macro, so branding it once covers password-reset, email-verification and
  executeActions (the account-creation invite) without touching those files.

  Deliberate constraints, all of them email-client reality rather than preference:
    - Table layout and INLINE styles. Gmail strips <style> from the <head>, Outlook
      ignores most modern CSS, and no client loads a webfont.
    - System font stack, not Bricolage/Hanken. Self-hosting cannot reach a mail
      client, and the alternative -- a Google Fonts <link> -- would break WS-05's
      zero-outbound-request rule and leak the recipient's open to a third party.
    - NO images, not even the logo mark. Most clients block remote images by
      default, so an <img> lockup renders as a broken box on first open. The
      wordmark is live text in the brand green instead, which always renders.
    - Light only. prefers-color-scheme support across mail clients is too patchy to
      be worth a second palette here.

  Colors are the same literals as the login theme's tokens; see
  login/resources/css/login.css for their design-system provenance.
-->
<#macro emailLayout>
<html lang="${locale.language}" dir="${(ltr)?then('ltr','rtl')}">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="color-scheme" content="light" />
</head>
<body style="margin:0; padding:0; background-color:#faf8f4; -webkit-text-size-adjust:100%;">
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:#faf8f4;">
        <tr>
            <td align="center" style="padding:32px 16px;">

                <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="max-width:520px;">

                    <#-- Wordmark -->
                    <tr>
                        <td align="center" style="padding-bottom:20px; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:20px; font-weight:700; letter-spacing:-0.015em; color:#196a51;">
                            TechGarden
                        </td>
                    </tr>

                    <#-- Card -->
                    <tr>
                        <td style="background-color:#ffffff; border:1px solid #e6e1d6; border-radius:10px; padding:32px 28px; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:16px; line-height:1.5; color:#262219;">
                            <#nested>
                        </td>
                    </tr>

                    <#-- Footer -->
                    <tr>
                        <td align="center" style="padding-top:20px; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:13px; line-height:1.5; color:#6e6557;">
                            <#-- Neutral on purpose: this macro also wraps the account invite, where
                                 "because you signed in" would be untrue. -->
                            Sent by TechGarden
                        </td>
                    </tr>

                </table>

            </td>
        </tr>
    </table>
</body>
</html>
</#macro>

<#--
  The call-to-action button.

  It lives here, in a template, rather than inside a message string on purpose:
  message HTML is rendered through kcSanitize(), whose allow-list may drop the
  inline style attributes an email button is entirely made of. Markup in a template
  is not sanitized, so the button is deterministic. Messages carry prose only.

  Belt and braces for Outlook, which ignores padding on <a>: the padding sits on the
  <td> and the <a> fills it, so the whole cell is the click target either way.

  There is deliberately NO "if the button does not work, paste this link" fallback.
  A Keycloak action token is ~700 characters, and printing it turns the email into a
  wall of base64 that dwarfs the actual message. It is also redundant: Keycloak sends
  every email as multipart with a text/plain part (base/email/text/*.ftl, which we
  inherit) that already carries the bare URL, and that is the part any client
  incapable of rendering this button will show. Even with all CSS stripped, the
  button degrades to an ordinary clickable link.
-->
<#macro emailButton href label>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:24px 0;">
    <tr>
        <td align="center" bgcolor="#1e8263" style="border-radius:6px;">
            <a href="${href}" style="display:inline-block; padding:14px 28px; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif; font-size:16px; font-weight:600; line-height:1; color:#ffffff; text-decoration:none; border-radius:6px;">${label}</a>
        </td>
    </tr>
</table>
</#macro>
