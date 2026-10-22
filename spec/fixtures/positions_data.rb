# frozen_string_literal: true

class PositionsData < LowData
  self.table = :users

  def chain = Users[:username] + Posts[:title] + Comments[:body]
  def grouped = Users[:username] + (Posts[:title] + Comments[:body])
  def siblings_with_path = Users[:username] + [Posts[:title] + Comments[:body], Likes[:id]]
  def siblings_chained = Posts[:title] + Comments[:body] + Likes[:id]
  def siblings_sorted = Users[:username] + [Posts[:title] ^ -Col[:views] * 1, Likes[:id]]
  def after_array = Posts[:title] + [Comments[:body]] + Likes[:id]
  def array_of_values = Posts[:title] + [:body]
  def reach_back = Users[:username] + Posts[:title] + Comments[:body] + Likes(:user_id)[:id]
  def reach_back_outside = Posts[:title] + Comments[:body] + Likes(:user_id)[:id]
  def named_in_join = Users[:username] + (Posts[:title] & Likes(:post_id)[:id])
  def join_in_chain = Users[:username] + (Posts[:title] & Likes[:id])
  def join_adjacent = Users[:username] & Posts[:title] & Likes[:id]
  def join_unlinked = Users[:username] & Posts[:title] & Reviews[:rating]
  def join_reach_back = Users[:username] & Posts[:title] & Reviews(:author_id)[:rating]
end
