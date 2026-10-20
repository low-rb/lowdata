# frozen_string_literal: true

class UsersData < LowData
  def ambiguous = Table[:username, :title]
  def many_keys = Table[:username, :rating]
end
