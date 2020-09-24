# frozen_string_literal: true

# Base helper for helpers
module BaseHelper
  def ensure_array(obj)
    case obj
    when Hash
      [obj]
    else
      Array(obj)
    end
  end
end
