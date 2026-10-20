# frozen_string_literal: true

class SortedPostsData < LowData
  self.table = :posts

  def sorted = Posts[:title] ^ Col[:views]
  def sorted_many = Posts[:title] ^ Col[:user_id, :title]
  def sorted_desc = Posts[:title] ^ -Col[:views, :title]
  def sorted_mixed = Posts[:title] ^ -Col[:user_id] + Col[:title]
  def sorted_twice = Posts[:title] ^ Col[:user_id] ^ -Col[:title]
  def limited = Posts[:title] * 2
  def sorted_limited = Posts[:title] ^ -Col[:views] * 1
  def sorted_then_limited = (Posts[:title] ^ Col[:id]) * 2
  def ranged = Posts[:title] ^ Col[:id][1...3]
  def ranged_endless = Posts[:title] ^ Col[:id][1..]
  def paged(page) = (Posts[:title] ^ Col[:id] / 2)[page]
  def paged_unsorted = (Posts[:title] / 2)[0]
  def pages = Posts[:title] ^ Col[:id] / 2
  def paged_unpicked = Posts[:title] ^ Col[:id] / 2
  def sorted_filtered = Posts(user_id: 1..)[:title] ^ -Col[:id]
  def sorted_join = Users[:username] & Posts[:title] ^ -Col[:views]
  def sorted_join_ambiguous = Users[:username] & Posts[:title] ^ Col[:id]
  def sorted_join_missing = Users[:username] & Posts[:title] ^ Col[:missing]
  def sorted_left_join = Users[:username] < Posts[:title] ^ Col[:views]
  def sorted_left_join_parenthesized = (Users[:username] < Posts[:title]) ^ Col[:username]
  def limited_join = Users[:username] & Posts[:title] * 1
  def sorted_inverted = Table[:username, :title] ^ -Col[:username]
  def sorted_nested = Users[:username, Posts[:title] ^ -Col[:views]] ^ -Col[:username]
  def limited_nested = Posts[:title, Likes[:id] ^ -Col[:id] * 1]
  def ranged_nested = Posts[:title, Likes[:id] ^ Col[:id][1..]]
  def limited_chain = Users[:username] + Likes[:id] * 1
  def sorted_chain = Users[:username] + Posts[:title] ^ -Col[:username]
  def sort_by_symbol = Posts[:title] ^ :views
  def limit_by_float = Posts[:title] * 1.5
  def limit_twice = Posts[:title] * 1 * 2
end
