module IAddNewsViaEmail

  class UnauthorizedAction < StandardError; end
  class MissingInformation < StandardError; end

  NEWS_CREATION = "news"
  NEWS_REPLY_SUBJECT_RE = %r{\[([^\]]+)\]\sNews:\s(.+)}

  def self.included(base)
    base.class_eval do

      alias_method :dispatch_orig, :dispatch

      private

        def dispatch
          logger.info "AddNewsViaEmail dispatch" if logger && logger.info
          email_type = get_keyword(:type, {:override => true})
          if m = email.subject.match(NEWS_REPLY_SUBJECT_RE)
            receive_news_comment(m[1], m[2])
          elsif email_type.to_s.downcase == NEWS_CREATION
            receive_news
          else
            dispatch_orig
          end
        rescue ActiveRecord::RecordInvalid => e
          # TODO: send an email to the user
          logger.error e.message if logger
          false
        rescue MissingInformation => e
          # TODO: send an email to the user
          logger.error "IAddNewsViaEmail::MailHandler: missing information from #{user}: #{e.message}" if logger
          false
        rescue UnauthorizedAction => e
          logger.error "IAddNewsViaEmail::MailHandler: unauthorized attempt from #{user}" if logger
          false
        end

        def receive_news
          begin
            my_log = get_keyword(:log, {:override => true}).to_s == "true"
            my_logger = Logger.new(File.new("#{RAILS_ROOT}/log/i_add_news_via_email.log", "a+")) if my_log
            my_logger.level = Logger::DEBUG if my_log
            my_logger.debug("Start message") if my_log
            logger.info "IAddNewsViaEmail::MailHandler: receiving news" if logger && logger.info
            project, summary, reminders, revision, cis, ooiu, news_body = get_info_from_mail(my_logger, my_log)
            # check permission
            raise UnauthorizedAction unless user.allowed_to?(:manage_news, project)
            news_body, any_issues_updated = update_issues(news_body, project, reminders, revision, cis, my_logger, my_log)
            # if news desc is empty
            my_logger.debug("ckeck if news body is blank? #{news_body.blank?}") if my_log
            raise MissingInformation.new("No News description") if news_body.blank?
            news = News.new(:title => email.subject.chomp, :author => user, :project => project,
              :summary => summary.to_s, :description => news_body)
            my_logger.debug("News save condition ((ooiu and any_issues_updated) or !ooiu): #{(ooiu and any_issues_updated) or !ooiu}") if my_log
            save_news(news, my_logger, my_log) if (ooiu and any_issues_updated) or !ooiu
          rescue Exception => e
            my_logger.debug("IAddNewsViaEmail::EXCEPTION::BEGIN") if my_log
            my_logger.debug(e.to_s) if my_log
            my_logger.debug(e.backtrace.join("\n")) if my_log
            my_logger.debug("IAddNewsViaEmail::EXCEPTION::END") if my_log
            logger.error "IAddNewsViaEmail::MailHandler: news ##{news.id}: #{e.to_s}"
          end
          return true
        end

        def receive_news_comment(identifier, title)
          project = Project.find_by_identifier(identifier)
          # check permission
          raise UnauthorizedAction unless user.allowed_to?(:comment_news, project)
          news = News.find(:first, :conditions => {:project_id => project.id, :title => title})
          comment = Comment.new(:commented_type => "News", :author => user, :comments => plain_text_body.to_s)
          news.comments << comment
          logger.info "IAddNewsViaEmail::MailHandler: news comment ##{comment.id} created by #{user}" if logger && logger.info
          comment
        end
        
        def save_news(news, my_logger, my_log)
          n_saved = news.save
          my_logger.debug("news saved? #{n_saved}") if my_log
          my_logger.debug("news errors: #{news.errors.to_s}") if my_log and !n_saved
          Mailer.deliver_news_added(news) if Setting.notified_events.include?('news_added')
          logger.info "IAddNewsViaEmail::MailHandler: news ##{news.id} created by #{user}" if logger && logger.info
        end

        def update_issues(news_body, project, reminders, revision, cis, my_logger, my_log)
          any_issues_updated = false
          if !revision.blank?
            my_logger.debug("revision OK") if my_log
            logger.info "IAddNewsViaEmail::MailHandler: revision OK" if logger && logger.info
            if project.repository and user.allowed_to?(:manage_repository, project)
              Repository.fetch_changesets
              my_logger.debug("repo fetch changes ok") if my_log
              logger.info "IAddNewsViaEmail::MailHandler: repo fetch changes ok" if logger && logger.info
              currentry_deployed_cs = Changeset.find(:first,
                :conditions => ["revision = ? and repository_id = ?", revision, project.repository.id])
              my_logger.debug("currentry_deployed_cs.id: #{currentry_deployed_cs.id}") if my_log
              if !currentry_deployed_cs.nil?
                logger.info "IAddNewsViaEmail::MailHandler: currently deployed cs exists" if logger && logger.info
                issues_updated = []
                not_deployed_changesets = project.repository.changesets.find(:all,
                  :conditions => ["committed_on <= ? and deployed = 0 and repository_id = ?",
                    currentry_deployed_cs.committed_on, project.repository.id])
                my_logger.debug("not_deployed_changesets.id's: #{not_deployed_changesets.map(&:id).join(', ')}") if my_log
                logger.info "IAddNewsViaEmail::MailHandler: change issue status? #{cis}" if logger && logger.info
                reminders_array = [] if reminders
                not_deployed_changesets.each do |ndc|
                  my_logger.debug("processing cs: #{ndc.id}; issues count: #{ndc.issues.length}") if my_log
                  my_logger.debug("reminders: #{ndc.comments.scan(/reminder: (.+)/).to_s};") if my_log and reminders
                  reminders_array << ndc.comments.scan(/reminder: (.+)/) if reminders
                  logger.info "IAddNewsViaEmail::MailHandler: cs id = #{ndc.id}" if logger && logger.info
                  ndc.issues.each do |ndc_i|
                    my_logger.debug("processing issue: #{ndc_i.id}; permission to edit: #{user.allowed_to?(:edit_issues, project)}") if my_log
                    if cis and user.allowed_to?(:edit_issues, project)
                      my_logger.debug("status id: #{ndc_i.status_id} == settings id: #{Setting[:commit_fix_status_id].to_i}") if my_log
                      if ndc_i.status_id == Setting[:commit_fix_status_id].to_i
                        logger.info "IAddNewsViaEmail::MailHandler: issue id = #{id}" if logger && logger.info
                        ndc_i.status_id = Setting[:commit_deployed_status_id].to_i
                        i_save = ndc_i.save
                        my_logger.debug("issue saved?: #{i_save}") if my_log
                        any_issues_updated = true
                        issues_updated << "##{ndc_i.id}"
                      end
                    end
                  end
                  ndc.deployed = true
                  c_saved = ndc.save
                  my_logger.debug("ndc saved?: #{c_saved}") if my_log
                end
                logger.info "IAddNewsViaEmail::MailHandler: issues: #{issues_updated.join(', ')}" if logger && logger.info
                my_logger.debug("are there issues which were updated?: #{!issues_updated.empty?}") if my_log
                my_logger.debug("are there any reminders?: #{reminders_array.flatten.join("\n")}") if my_log and reminders
                news_body = "#{news_body}\nDeployed: #{issues_updated.join(', ')}" if !issues_updated.empty?
                news_body = "#{news_body}\nReminders:\n#{reminders_array.flatten.join("\n")}" if reminders and !reminders_array.flatten.join("\n").blank?
                my_logger.debug("news body: #{news_body}") if my_log
              end
            end
          end
          return news_body, any_issues_updated
        end

        def get_info_from_mail(my_logger, my_log)
          project, summary, reminders, revision, cis, ooiu, news_body =
            target_project, get_keyword(:summary, {:override => true}), get_keyword(:reminders, {:override => true}).to_s == "true",
              get_keyword(:revision, {:override => true}), get_keyword(:changeissuestatus, {:override => true}).to_s == "true",
              get_keyword(:only_on_issue_update, {:override => true}).to_s == "true", plain_text_body.strip.to_s
          my_logger.debug("project: #{project}") if my_log
          my_logger.debug("summary: #{summary}") if my_log
          my_logger.debug("revision: #{revision}") if my_log
          my_logger.debug("change_issue_status: #{cis}") if my_log
          my_logger.debug("only_on_issue_update: #{ooiu}") if my_log
          my_logger.debug("user mail: #{user.mail}; authorized?: #{user.allowed_to?(:manage_news, project)}") if my_log
          my_logger.debug("news_body: #{news_body}") if my_log
          return project, summary, reminders, revision, cis, ooiu, news_body
        end
    end
  end

end
