# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

ActionController::Routing::Routes.draw do |map|
  map.connect 'settings/update',        :controller => 'redmine_extended_reminder/settings', :action => :update
  map.connect 'settings/send_reminder', :controller => 'redmine_extended_reminder/settings', :action => :send_reminder
end
