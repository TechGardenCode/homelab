<#--
  Overrides base/email/html/executeActions.ftl -- the account-creation invite.

  This is the email WS-04 proved as the hand-provisioning trigger (Admin REST
  PUT /admin/realms/{realm}/users/{id}/execute-actions-email). Per ADR-0052 there is
  no self-service signup, so for a friend joining TechGarden this is the FIRST email
  they ever receive from us. It gets the same button treatment as the others.

  {0}=link  {1}=linkExpiration  {2}=realmName  {3}=requiredActionsText
  {4}=formatted expiration
-->
<#outputformat "plainText">
<#assign requiredActionsText><#if requiredActions??><#list requiredActions><#items as reqActionItem>${msg("requiredAction.${reqActionItem}")}<#sep>, </#sep></#items></#list></#if></#assign>
</#outputformat>

<#import "template.ftl" as layout>
<@layout.emailLayout>
${kcSanitize(msg("executeActionsBodyHtml", link, linkExpiration, realmName, requiredActionsText, linkExpirationFormatter(linkExpiration)))?no_esc}
<@layout.emailButton href=link label=msg("executeActionsButton") />
${kcSanitize(msg("executeActionsFooterHtml", linkExpirationFormatter(linkExpiration)))?no_esc}
</@layout.emailLayout>
