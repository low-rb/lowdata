# frozen_string_literal: true

class RenamedPostsData < LowData
  self.table = :posts

  def renamed = Posts[:id, headline: :title]
  def only = Posts[headline: :title]
  def joined = Users[:username, user_id: :id] & Posts[:title, post_id: :id]
  def nested = Users[Posts[headline: :title], handle: :username]
  def nested_join = Users[:username] + (Posts[headline: :title] & Comments[:body])
  def under_join = (Users[handle: :username] & Posts[:title]) + Comments[:body]
  def sorted = Posts[headline: :title] ^ -Col[:title]
  def inverted = Table[:title, author: :username]
  def backwards = Posts[title: :headline]
  def missing = Posts[headline: :missing]
  def existing = Posts[title: :views]
  def twice = Posts[:views, views: :title]
  def nested_clash = Posts[Users[:username], user: :title]
  def inverted_backwards = Table[username: :author]
end
