# frozen_string_literal: true

class ArticlesData < LowData
  self.table = :posts

  def all = Table[:title]
end
