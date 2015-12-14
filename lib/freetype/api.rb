require 'freetype/c'
require 'freetype/error'

module FreeType
  # high level API for freetype wrapping by FFI
  module API
    module IOInterface
      def open(*args)
        i = new(*args)
        if block_given?
          begin
            yield i
          ensure
            i.close
          end
        else
          i
        end
      end
    end

    class Library
      extend IOInterface
      include C

      def initialize
        @library = ::FFI::MemoryPointer.new(:pointer)
        err = FT_Init_FreeType(@library)
        raise FreeType::Error.find(err) unless err == 0
      end

      def face_open(font)
        Face.open(pointer, font) do |f|
          yield f
        end
      end

      def pointer
        @library.get_pointer(0)
      end

      def version
        amajor = ::FFI::MemoryPointer.new(:int)
        aminor = ::FFI::MemoryPointer.new(:int)
        apatch = ::FFI::MemoryPointer.new(:int)
        FT_Library_Version(@library.get_pointer(0), amajor, aminor, apatch)
        "#{amajor.get_int(0)}.#{aminor.get_int(0)}.#{apatch.get_int(0)}"
      end

      def close
        err = FT_Done_Library(@library.get_pointer(0))
        raise FreeType::Error.find(err) unless err == 0
        @library.free
      end
    end

    class Face
      extend IOInterface
      include C

      attr_reader :face
      def initialize(library, font)
        @library = library
        @font = font
        @outline = nil
        f = ::FFI::MemoryPointer.new(:pointer)
        err = FT_New_Face(@library, @font, 0, f)
        raise FreeType::Error.find(err) unless err == 0
        @face = FT_FaceRec.new(f.get_pointer(0))
      end

      def select_charmap(enc_code)
        err = FT_Select_Charmap(@face, enc_code)
        raise FreeType::Error.find(err) unless err == 0
      end

      def set_char_size(char_width, char_height, horz_resolution, vert_resolution)
        err = FT_Set_Char_Size(@face, char_width, char_height, horz_resolution, vert_resolution)
        raise FreeType::Error.find(err) unless err == 0
      end

      # TODO: Should be use FT_Get_Glyph
      def notdef
        glyph("\x00")
      end

      # TODO
      # Should be use FT_Get_Glyph and FT_Done_Glyph
      # Because return value will be change after call FT_Load_Char
      def glyph(char)
        load_char(char)
        Glyph.new(@face[:glyph])
      end

      def char_index(char)
        FT_Get_Char_Index(@face, char.ord)
      end

      def bbox
        bbox = @face[:bbox]
        BBox.new(bbox[:xMin], bbox[:xMax], bbox[:yMin], bbox[:yMax])
      end

      def kerning(before_char, after_char)
        get_kerning(before_char, after_char, :FT_KERNING_DEFAULT)
      end
      alias_method :kerning_default, :kerning

      def kerning_unfitted(before_char, after_char)
        get_kerning(before_char, after_char, :FT_KERNING_UNFITTED)
      end

      def kerning_unscaled(before_char, after_char)
        get_kerning(before_char, after_char, :FT_KERNING_UNSCALED)
      end

      def close
        err = FT_Done_Face(@face)
        raise FreeType::Error.find(err) unless err == 0
      end

      private

      def get_kerning(before_char, after_char, kerning_mode)
        if before_char.nil? || before_char == ''.freeze || after_char.nil? || after_char == ''.freeze
          return Vector.new(0, 0)
        end

        v = FT_Vector.new
        err = FT_Get_Kerning(
          @face,
          char_index(before_char),
          char_index(after_char),
          kerning_mode,
          v,
        )
        raise FreeType::Error.find(err) unless err == 0

        Vector.new(v[:x], v[:y])
      end

      def load_char(char)
        err = FT_Load_Char(@face, char.ord, FreeType::C::FT_LOAD_DEFAULT)
        unless err == 0
          e = FreeType::Error.find(err)
          if FreeType::Error::Invalid_Size_Handle === e
            warn 'should be call FT_Set_Char_Size before FT_Load_Char'
          end
          raise e
        end
      end
    end

    class Glyph
      def initialize(glyph)
        @glyph = glyph
      end

      def metrics
        @glyph[:metrics]
      end

      def outline
        Outline.new(@glyph[:outline])
      end

      def space_width
        @glyph[:metrics][:horiAdvance]
      end
    end

    class Outline
      include C

      def initialize(outline)
        @outline = outline
      end

      def points
        @points ||= begin
          points = @outline[:n_points].times.map do |i|
            FT_Vector.new(@outline[:points] + i * FT_Vector.size)
          end
          points.zip(tags).map do |(point, tag)|
            Point.new(tag, point[:x], point[:y])
          end
        end
      end

      def contours
        @outline[:contours].get_array_of_short(0, @outline[:n_contours])
      end

      def tags
        @outline[:tags].get_array_of_char(0, @outline[:n_points])
      end

      def to_svg_path
        end_ptd_of_counts = contours
        contours = []
        contour = []
        points.each.with_index do |point, index|
          contour << point
          if index == end_ptd_of_counts.first
            end_ptd_of_counts.shift
            contours << contour
            contour = []
          end
        end

        path = []
        contours.each do |contour|
          first_pt = contour.first
          last_pt = contour.last
          curve_pt = nil
          start = 0
          if first_pt.on_curve?
            curve_pt = nil
            start = 1
          else
            if last_pt.on_curve?
              first_pt = last_pt
            else
              first_pt = Point.new(0, (first_pt.x + last_pt.x) / 2, (first_pt.y + last_pt.y) / 2)
            end
            curve_pt = first_pt
          end
          path << ['M', first_pt.x, -first_pt.y]

          prev_pt = nil
          (start...contour.length).each do |j|
            pt = contour[j]
            prev_pt = if j == 0
              first_pt
            else
              contour[j - 1]
            end

            if prev_pt.on_curve? && pt.on_curve?
              path << ['L', pt.x, -pt.y]
            elsif prev_pt.on_curve? && !pt.on_curve?
              curve_pt = pt
            elsif !prev_pt.on_curve? && !pt.on_curve?
              path << ['Q', prev_pt.x, -prev_pt.y, (prev_pt.x + pt.x) / 2, -((prev_pt.y + pt.y) / 2)]
              curve_pt = pt
            elsif !prev_pt.on_curve? && pt.on_curve?
              path << ['Q', curve_pt.x, -curve_pt.y, pt.x, -pt.y]
              curve_pt = nil
            else
              raise
            end
          end

          next unless first_pt != last_pt
          if curve_pt
            path << ['Q', curve_pt.x, -curve_pt.y, first_pt.x, -first_pt.y]
          else
            path << ['L', first_pt.x, -first_pt.y]
          end
        end
        path << ['z']

        path.map { |(command, *args)|
          "#{command}#{args.join(' ')}"
        }.join('')
      end
    end

    Point = Struct.new(:tag, :x, :y) do
      def on_curve?
        tag & 0x01 != 0
      end
    end

    Vector = Struct.new(:x, :y)
    BBox = Struct.new(:x_min, :x_max, :y_min, :y_max)
  end
end
