module TrackerAccessibleIssuePatch
  def self.included(base)

    base.class_eval do
      # ========= start patch visible_condition =========
      unless Issue.respond_to?(:visible_condition_block)
        # move logic for patching logic in separate method in order to avoid possible conflicts with another plugins

        # Returns a SQL conditions string used to find all issues visible by the specified user on it's index page
        def self.visible_condition(user, options={})
          Project.allowed_to_condition(user, :view_issues, options) do |role, user|
            visible_condition_block(role, user)
          end
        end

        # this is origin logic which is moved in separate method for patching purposes
        def self.visible_condition_block(role, user)
          if user.logged?
            case role.issues_visibility
            when 'all'
              nil
            when 'default'
              user_ids = [user.id] + user.groups.map(&:id)
              "(#{table_name}.is_private = #{connection.quoted_false} OR #{table_name}.author_id = #{user.id} OR #{table_name}.assigned_to_id IN (#{user_ids.join(',')}))"
            when 'own'
              user_ids = [user.id] + user.groups.map(&:id)
              "(#{table_name}.author_id = #{user.id} OR #{table_name}.assigned_to_id IN (#{user_ids.join(',')}))"
            else
              '1=0'
            end
          else
            "(#{table_name}.is_private = #{connection.quoted_false})"
          end
        end
      end

      # patch for visible_condition_block
      def self.visible_condition_block_with_tracker_accessible(role, user)
        if user.logged? && role.issues_visibility == 'issues_tracker_accessible'
          tracker_ids = role.tracker_accessible_permission.map(&:to_i).delete_if(&:zero?)
          "(#{table_name}.tracker_id IN (#{tracker_ids.join(',')}))"
        else
          visible_condition_block_without_tracker_accessible(role, user)
        end
      end

      class << self
        # use alias_method_chain to have origin methods and patched ones.
        # it will help to patch origin logic in other places (=plugins)
        alias_method_chain :visible_condition_block, :tracker_accessible
      end
      # ========= end patch visible_condition =========

      # ========= start patch visible =========
      unless Issue.new.respond_to?(:visible_block)
        # move logic for patching logic in separate method in order to avoid possible conflicts with another plugins

        # Returns true if usr or current user is allowed to view the issue's show page
        def visible?(usr=nil)
          (usr || User.current).allowed_to?(:view_issues, self.project) do |role, user|
            visible_block(role, user)
          end
        end

        # this is origin logic which is moved in separate method for patching purposes
        def visible_block(role, user)
          if user.logged?
            case role.issues_visibility
            when 'all'
              true
            when 'default'
              !self.is_private? || (self.author == user || user.is_or_belongs_to?(assigned_to))
            when 'own'
              self.author == user || user.is_or_belongs_to?(assigned_to)
            else
              false
            end
          else
            !self.is_private?
          end
        end
      end

      # patch for visible_block
      def visible_block_with_tracker_accessible(role, user)
        if user.logged? && role.issues_visibility == 'issues_tracker_accessible'
          tracker_ids = role.tracker_accessible_permission.map(&:to_i).delete_if(&:zero?)
          tracker_ids.include?(tracker_id)
        else
          visible_block_without_tracker_accessible(role, user)
        end
      end
      # use alias_method_chain to have origin methods and patched ones.
      # it will help to patch origin logic in other places (=plugins)
      alias_method_chain :visible_block, :tracker_accessible
      # ========= end patch visible =========
    end

  end
end