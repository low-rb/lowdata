# frozen_string_literal: true

class NestedJoinsData < LowData
  self.table = :users

  def nest_after_join = (Users[:username] & Posts[:title]) + Comments[:body]
  def nest_join = Users[:username] + (Posts[:title] & Comments[:body])
  def nest_left_join = Users[:username] + (Posts[:title] < Comments[:body])
  def nest_join_reordered = Users[:username] + (Comments[:body] & Posts[:title])
  def nest_join_sorted = Users[:username] + (Posts[:title] & Comments[:body] ^ -Col[:body])
  def nest_join_limited = Users[:username] + (Posts[:title] & Comments[:body] ^ Col[:body] * 1)
  def nest_join_sorted_outside = Users[:username] + (Posts[:title] & Comments[:body]) ^ Col[:body]
  def nest_join_filtered = Users[:username] + (Posts(views: 100..)[:title] < Comments[:body])
  def nest_join_named = Users[:username, written: Posts[:title] & Comments[:body]]
  def nest_join_in_brackets = Users[:username, Posts[:title] & Comments[:body]]
  def nest_join_one_side = Comments[:body] + (Posts[:title] & Users[:username])
  def nest_join_both_link = Users[:username] + (Posts[:title] & Likes[:id])
  def nest_join_foreign_key = Users[:username] + (Posts(:user_id)[:title] & Likes[:id])
  def nest_join_other_foreign_key = Users[:username] + (Posts[:title] & Likes(:user_id)[:id])
  def nest_join_unlinked = Users[:username] + (Comments[:body] & Posts[:title] & Tags[:name])
  def nest_under_join_one = (Posts[:title] & Comments[:body]) + Users[:username]
  def nest_under_join_sorted = (Users[:username] & Posts[:title]) + Comments[:body] ^ -Col[:title]
  def nest_under_join_both_link = (Users[:username] & Posts[:title]) + Likes[:id]
  def nest_under_join_foreign_key = (Users[:username] & Posts[:title]) + Likes(:post_id)[:id]
  def nest_join_nested = Users[:username] + (Posts[:title] & (Comments[:body] + Likes[:id]))
end
