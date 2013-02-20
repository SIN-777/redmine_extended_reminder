require_dependency 'mailer'

module RedmineExtendedReminder
  module MailerModelPatch
    def self.included(base)
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)

      base.class_eval do
        # replace class methods
        helper :extended_reminder
        class << self
          alias_method_chain :reminders, :patch
        end

        # replace instance methods
        alias_method_chain :reminder, :patch
      end
    end
  end

  module ClassMethods
    def reminders_with_patch(options={})
      # Non-working days setting is supported in Redmine 2.2 or higher.
      if Redmine::VERSION.to_a[0..1].join('.').to_f >= 2.2
        if Setting.plugin_redmine_extended_reminder[:disable_on_non_woking_days].to_i != 0
          date_calc = Object.new
          date_calc.extend Redmine::Utils::DateCalculation
          return nil if date_calc.non_working_week_days.include?(Date.today.wday)
        end
      end

      days_override = Setting.plugin_redmine_extended_reminder[:days].to_i
      options[:days] = days_override if days_override > 0
      reminders_without_patch(options)

      overdue_version_issues_reminders(options)
    end

    def overdue_version_issues_reminders(options)
      overdue_versions = Version.find(:all, :conditions => ['effective_date is not NULL AND effective_date < ?', Date.today])
      overdue_version_issues = overdue_versions.inject([]){|res, v| res += v.fixed_issues.select{|issue| !issue.closed?}}

      reminders = {}
      overdue_version_issues.each do |issue|
        reminders[issue.project.id] ||= {}
        (reminders[issue.project.id][issue.assigned_to_id] ||= []) << issue
      end

      reminders.each do |project_id, user_issues|
        user_issues.each do |user_id, issues|
          project = Project.find(project_id)
          project_admins = project.users.select{|user| user.admin}
          user = User.find(user_id)
          deliver_overdue_version_issues_reminder(user, project_admins, issues)
        end
      end
    end

  end

  module InstanceMethods
    def reminder_with_patch(user, issues, days)
      saved_status = ActionMailer::Base.perform_deliveries
      if user.pref[:extended_reminder_no_reminders]
        ActionMailer::Base.perform_deliveries = false
      end
      @issues_by_date = issues.sort_by(&:due_date).group_by(&:due_date)
      @count = issues.size
      reminder_without_patch(user, issues, days)
    ensure
      ActionMailer::Base.perform_deliveries = saved_status
    end

    def overdue_version_issues_reminder(user, project_admins, issues)
      version_grouped_issues = {}
      versions = issues.map(&:fixed_version).compact.uniq.sort_by(&:id)
      versions.each do |version|
        version_grouped_issues[version.id] = issues.select{|issue| issue.fixed_version_id == version.id}
      end

      set_language_if_valid user.language
      recipients user.mail
      cc project_admins.map(&:mail)
      subject l(:extended_reminder_version_overdue_issues_mail_subject, :count => issues.size)
      body :versions => versions,
           :version_grouped_issues => version_grouped_issues,
           :issues => issues,
           :issues_url => url_for(:controller => 'issues', :action => 'index',
                                  :set_filter => 1, :assigned_to_id => user.id)
      render_multipart('overdue_version_issues_reminder', body)
    end
  end
end

unless Mailer.included_modules.include?(RedmineExtendedReminder::MailerModelPatch)
  Mailer.send(:include, RedmineExtendedReminder::MailerModelPatch)
end
