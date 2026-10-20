# frozen_string_literal: true

# Repositories are defined with the class keyword so constants like `Users` resolve through LowData.const_missing.
class PostsData < LowData
  def full = Users[:username] + Posts[:title]
  def inner = Users[:username] & Posts[:title]
  def left = Users[:username] < Posts[:title]
  def right = Users[:username] > Posts[:title]
  def all_columns = Users[] & Posts[]
  def chained = Users[:username] & Posts[:title] & Comments[:body]
  def parenthesized = (Users[:username] < Posts[:title]) & Comments[:body]
  def nested = Users[:username] < Posts[:title] & Comments[:body]
  def unrelated = Users[:username] & Tags[:name]
  def ambiguous = Users[:username] & Reviews[:rating]
  def self_join = Users[:username] & Users[:id]
  def value = Users[:username] & :posts
  def type = Users[:username] & String
  def inverted = Table[:username, :title, :body]
  def inverted_order = Table[:title, :username]
  def inverted_unrelated = Table[:name]
  def inverted_missing = Table[:missing]
  def inverted_join = Table[:title] & Users[:username]
end
