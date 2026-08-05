<#--
  Overrides base/email/html/email-verification.ftl. See password-reset.ftl for why
  the CTA lives in the template rather than the message.
  {0}=link  {1}=linkExpiration  {2}=realmName  {3}=formatted expiration
-->
<#import "template.ftl" as layout>
<@layout.emailLayout>
${kcSanitize(msg("emailVerificationBodyHtml", link, linkExpiration, realmName, linkExpirationFormatter(linkExpiration)))?no_esc}
<@layout.emailButton href=link label=msg("emailVerificationButton") />
${kcSanitize(msg("emailVerificationFooterHtml", linkExpirationFormatter(linkExpiration)))?no_esc}
</@layout.emailLayout>
