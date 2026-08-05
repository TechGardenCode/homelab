<#--
  Overrides base/email/html/password-reset.ftl so the reset link renders as a real
  button. The prose still comes from the message bundle (passwordResetBodyHtml);
  only the CTA moved into the template, because message HTML is sanitized.
  {0}=link  {1}=linkExpiration  {2}=realmName  {3}=formatted expiration
-->
<#import "template.ftl" as layout>
<@layout.emailLayout>
${kcSanitize(msg("passwordResetBodyHtml", link, linkExpiration, realmName, linkExpirationFormatter(linkExpiration)))?no_esc}
<@layout.emailButton href=link label=msg("passwordResetButton") />
${kcSanitize(msg("passwordResetFooterHtml", linkExpirationFormatter(linkExpiration)))?no_esc}
</@layout.emailLayout>
