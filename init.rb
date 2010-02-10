require 'redmine' 
Redmine::Plugin.register :i_add_news_via_email do
  name 'I Add News Via Email'
  author 'Titas Norkūnas'
  description 'A plugin that enables news receiving via email'
  version '0.0.1'
end
MailHandler.send :include, IAddNewsViaEmail
