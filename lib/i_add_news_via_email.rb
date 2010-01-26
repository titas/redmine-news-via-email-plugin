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
          project = target_project
          summary = get_keyword(:summary, {:override => true})
          # check permission
          raise UnauthorizedAction unless user.allowed_to?(:manage_news, project)
          raise MissingInformation.new("No News description") if plain_text_body.blank?
          # should I check if description is empty and raise MissingInformation? This happens otherwise:
          # Validation failed: Description activerecord_error_blank
          news = News.new(:title => email.subject.chomp, :author => user, :project => project,
            :summary => summary.to_s, :description => plain_text_body.to_s)
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