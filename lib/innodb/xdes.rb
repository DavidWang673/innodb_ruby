# An InnoDB "extent descriptor entry" or "+XDES+". These structures are used
# in the +XDES+ entry array contained in +FSP_HDR+ and +XDES+ pages.
#
# Note the distinction between +XDES+ _entries_ and +XDES+ _pages_.
class Innodb::Xdes
  # Number of pages contained in an extent. InnoDB extents are normally
  # 64 pages, or 1MiB in size.
  PAGES_PER_EXTENT = 64

  # Number of bits per page in the +XDES+ entry bitmap field. Currently
  # +XDES+ entries store two bits per page, with the following meanings:
  #
  # * 1 = free (the page is free, or not in use)
  # * 2 = clean (currently unused, always 1 when initialized)
  BITS_PER_PAGE = 2

  # The bit value for a free page.
  BITMAP_BV_FREE  = 1

  # The bit value for a clean page (currently unused in InnoDB).
  BITMAP_BV_CLEAN = 2

  # The bitwise-OR of all bitmap bit values.
  BITMAP_BV_ALL = (BITMAP_BV_FREE | BITMAP_BV_CLEAN)

  # Size (in bytes) of the bitmap field in the +XDES+ entry.
  BITMAP_SIZE = (PAGES_PER_EXTENT * BITS_PER_PAGE) / 8

  # Size (in bytes) of the an +XDES+ entry.
  ENTRY_SIZE = 8 + Innodb::List::NODE_SIZE + 4 + BITMAP_SIZE

  # The values used in the +:state+ field indicating what the extent is
  # used for (or what list it is on).
  STATES = {
    1 => :free,       # The extent is completely empty and unused, and should
                      # be present on the filespace's FREE list.

    2 => :free_frag,  # Some pages of the extent are used individually, and
                      # the extent should be present on the filespace's
                      # FREE_FRAG list.

    3 => :full_frag,  # All pages of the extent are used individually, and
                      # the extent should be present on the filespace's
                      # FULL_FRAG list.

    4 => :fseg,       # The extent is wholly allocated to a file segment.
                      # Additional information about the state of this extent
                      # can be derived from the its presence on particular
                      # file segment lists (FULL, NOT_FULL, or FREE).
  }

  def initialize(page, cursor)
    @page = page
    extent_number = (cursor.position - page.pos_xdes_array) / ENTRY_SIZE
    start_page = page.offset + (extent_number * PAGES_PER_EXTENT)
    @xdes = {
      :start_page => start_page,
      :fseg_id    => cursor.get_uint64,
      :this       => {:page => page.offset, :offset => cursor.position},
      :list       => Innodb::List.get_node(cursor),
      :state      => STATES[cursor.get_uint32],
      :bitmap     => cursor.get_bytes(BITMAP_SIZE),
    }
  end

  # Return the stored extent descriptor entry.
  def xdes
    @xdes
  end

  # Iterate through all pages represented by this extent descriptor,
  # yielding a page status hash for each page, containing the following
  # fields:
  #
  #   :page   The page number.
  #   :free   Boolean indicating whether the page is free.
  #   :clean  Boolean indicating whether the page is clean (currently
  #           this bit is unused by InnoDB, and always set true).
  def each_page_status
    unless block_given?
      return Enumerable::Enumerator.new(self, :each_page_status)
    end

    xdes[:bitmap].bytes.each_with_index do |byte, byte_index|
      (0..3).each_with_index do |page, page_index|
        page_number = xdes[:start_page] + (byte_index * 4) + page_index
        page_bits = ((byte >> (page * BITS_PER_PAGE)) & BITMAP_BV_ALL)
        page_status = {
          :page   => page_number,
          :free   => (page_bits & BITMAP_BV_FREE  != 0),
          :clean  => (page_bits & BITMAP_BV_CLEAN != 0),
        }
        yield page_status
      end
    end

    nil
  end

  # Return the count of free pages (free bit is true) on this extent.
  def free_pages
    each_page_status.inject(0) { |sum, p| sum += 1 if p[:free]; sum }
  end

  # Return the count of used pages (free bit is false) on this extent.
  def used_pages
    PAGES_PER_EXTENT - free_pages
  end

  # Return the address of the previous list pointer from the list node
  # contained within the XDES entry. This is used by +Innodb::List::Xdes+
  # to iterate through XDES entries in a list.
  def prev_address
    xdes[:list][:prev]
  end

  # Return the address of the next list pointer from the list node
  # contained within the XDES entry. This is used by +Innodb::List::Xdes+
  # to iterate through XDES entries in a list.
  def next_address
    xdes[:list][:next]
  end
end