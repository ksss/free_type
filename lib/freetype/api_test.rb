require 'freetype/api'

module FreeTypeApiTest
  include FreeType::API

  def libopen
    Library.open do |lib|
      ['data/Prida01.otf', 'data/Starjedi.ttf'].each do |font|
        lib.face_open(font) do |f|
          f.set_char_size(0, 0, 300, 300)
          yield f
        end
      end
    end
  end

  def test_Library(t)
    lib = nil
    ret = Library.open do |l|
      lib = l

      unless /\A\d+\.\d+\.\d+\z/.match l.version
        t.error "return value break got #{l.version}"
      end

      :abc
    end
    if lib.nil?
      t.error('cannot get FT_Library in `open` with block')
    end
    if ret != :abc
      t.error 'want to return last value in block'
    end
  end

  def test_Face(t)
    face = nil
    Library.open do |lib|
      ['data/Prida01.otf', 'data/Starjedi.ttf'].each do |font|
        lib.face_open(font) do |f|
          face = f
          if f.char_index('a') == 0
            t.error('ascii char not defined this font')
          end
          if f.char_index('㍿') != 0
            t.error("I don't know why set character was defined in font")
          end

          v = f.kerning('A', 'W')
          unless v
            t.error('#kerning return object was changed')
          end
          unless Fixnum === v.x && Fixnum === v.y
            t.error('Not vector object. Check spec for FT_Get_Kerning()')
          end

          begin
            err = StringIO.new
            origerr = $stderr
            $stderr = err
            f.glyph('a')
          rescue FreeType::Error::Invalid_Size_Handle
            if err.string.empty?
              t.error('recommend warn miss?')
            end
          else
            t.error('check freetype spec')
          ensure
            $stderr = origerr
          end

          f.set_char_size(0, 0, 300, 300)

          bbox = f.bbox
          unless BBox === bbox
            t.error('FreeType::API::Face#bbox return value was break')
          end

          unless Glyph === f.glyph('a')
            t.error 'return value was break'
          end

          # unless Glyph === f.notdef
          #   t.error 'return value was break'
          # end
        end
      end
    end
    if face.nil?
      t.error('cannot get FT_Face in `open` with block')
    end
  end

  def test_glyph(t)
    libopen do |f|
      table = { 'a' => nil, 'b' => nil, 'c' => nil, 'd' => nil }
      table.each do |char, _|
        glyph = f.glyph(char)

        metrics = glyph.metrics
        unless FreeType::C::FT_Glyph_Metrics === metrics
          t.error 'return value was break'
        end

        space_width = glyph.space_width
        unless Fixnum === space_width
          t.error 'return value was break'
        end

        outline = glyph.outline
        unless Outline === outline
          t.error('FreeType::API::Face#outline return value was break')
        end
      end
    end
  end

  def test_outline(t)
    libopen do |f|
      table = { 'a' => nil, 'b' => nil, 'c' => nil, 'd' => nil }
      table.each do |char, _|
        outline = f.glyph(char).outline

        unless 0 < outline.points.length
          t.error('FT_Outline.points get failed from ffi')
        end

        unless outline.points.all? { |i| Point === i }
          t.error('Miss array of FreeType::API::Outline#points objects assignment')
        end

        unless outline.tags.all? { |i| Fixnum === i }
          t.error('Got values miss assigned from ffi')
        end

        unless outline.contours.all? { |i| Fixnum === i }
          t.error('Got values miss assigned from ffi')
        end

        table[char] = outline.points.map(&:x)
      end
      if table.values.uniq.length != table.length
        t.error 'char reference miss'
      end
    end
  end
end
