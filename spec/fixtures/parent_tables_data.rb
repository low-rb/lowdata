# frozen_string_literal: true

class ParentTablesData < LowData
  self.table = :notes

  def notes_with_photos = Notes[:title, Photos[:path] ^ Col[:id]]
  def photos_with_notes = Photos[:path, Notes[:title]] ^ Col[:id]
  def notes_joined = Notes[:title] & Photos[:path] ^ Col[:path]
  def notes_with_kind = Notes[:title, Content[:kind]]
end
