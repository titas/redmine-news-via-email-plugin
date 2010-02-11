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
          logger.info "IAddNewsViaEmail::MailHandler: receiving news" if logger && logger.info
          project = target_project
          summary = get_keyword(:summary, {:override => true})
          revision = get_keyword(:revision, {:override => true})
          change_issue_status = get_keyword(:changeissuestatus, {:override => true})
          # check permission
          raise UnauthorizedAction unless user.allowed_to?(:manage_news, project)
          news_body = plain_text_body.to_s
          cis = change_issue_status.to_s == "true"
          if !revision.blank?
            logger.info "IAddNewsViaEmail::MailHandler: revision OK" if logger && logger.info
            if project.repository
              Repository.fetch_changesets
              logger.info "IAddNewsViaEmail::MailHandler: repo fetch changes ok" if logger && logger.info
              currentry_deployed_cs = Changeset.find(:first,
                :conditions => ["revision = ? and repository_id = ?", revision, project.repository.id])
              if !currentry_deployed_cs.nil?
                logger.info "IAddNewsViaEmail::MailHandler: currently deployed cs exists" if logger && logger.info
                issues_updated = []
                not_deployed_changesets = project.repository.changesets.find(:all,
                  :conditions => ["committed_on <= ? and deployed = 0 and repository_id = ?",
                    currentry_deployed_cs.committed_on, project.repository.id])
                logger.info "IAddNewsViaEmail::MailHandler: change issue status? #{cis}" if logger && logger.info
                not_deployed_changesets.each do |ndc|
                  logger.info "IAddNewsViaEmail::MailHandler: cs id = #{ndc.id}" if logger && logger.info
                  ndc.issues.each do |ndc_i|
                    if cis
                      if ndc_i.status_id == Setting[:commit_fix_status_id].to_i
                        logger.info "IAddNewsViaEmail::MailHandler: issue id = #{id}" if logger && logger.info
                        ndc_i.status_id = Setting[:commit_deployed_status_id].to_i
                        ndc_i.save
                        issues_updated << "##{ndc_i.id}"
                      end
                    end
                  end
                  ndc.deployed = true
                  ndc.save
                end
                logger.info "IAddNewsViaEmail::MailHandler: issues: #{issues_updated.join(', ')}" if logger && logger.info
                news_body += "\nDeployed: #{issues_updated.join(', ')}" if !issues_updated.empty?
              end
            end
          end
          # if news desc is empty
          raise MissingInformation.new("No News description") if news_body.blank?
          news = News.new(:title => email.subject.chomp, :author => user, :project => project,
            :summary => summary.to_s, :description => news_body)
          news.save!
          Mailer.deliver_news_added(news) if Setting.notified_events.include?('news_added')
          logger.info "IAddNewsViaEmail::MailHandler: news ##{news.id} created by #{user}" if logger && logger.info
          news
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
    end
  end

end
