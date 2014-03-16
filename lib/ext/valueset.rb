module HealthDataStandards
  module SVS
    class ValueSet
      # include Mongoid::Document
      belongs_to :user
      belongs_to :bundle, class_name: "HealthDataStandards::CQM::Bundle"
      scope :by_user, ->(user) { where({'user_id'=>(user ? user.id : nil)}) }
    end
  end
end