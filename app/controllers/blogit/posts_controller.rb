module Blogit

  # Using explicit ::Blogit::ApplicationController fixes NoMethodError 'blogit_authenticate' in
  # the main_app
  class PostsController < ::Blogit::ApplicationController

    # If a layout is specified, use that. Otherwise, fall back to the default
    layout Blogit.configuration.layout if Blogit.configuration.layout

    # If using Blogit's Create, Update and Destroy actions AND ping_search_engines is
    # set, call ping_search_engines after these requests
    if Blogit.configuration.include_admin_actions
      after_filter :ping_search_engines, only: [:create, :update, :destroy], :if => lambda { Blogit.configuration.ping_search_engines }
    end

    # Raise a 404 error if the admin actions aren't to be included
    # We can't use blogit_conf here because it sometimes raises NoMethodError in main app's routes
    unless Blogit.configuration.include_admin_actions
      before_filter :raise_404, except: [:index, :show]
    end

    blogit_authenticate(except: [:index, :show, :tagged, :archives])
    before_filter :load_sidebar_data, only: [:index, :tagged, :archives, :show]

    def index
      respond_to do |format|
        format.xml {
          @posts = Post.active.order('published_at DESC')
        }
        format.html do
          @posts = blog_posts_scope.for_index(params[Kaminari.config.param_name])
        end
        format.rss {
          @posts = Post.active.order('published_at DESC')
        }
      end
    end

    def show
      @post = blog_posts_scope.find(params[:id])
    end

    def tagged
      param_name = params[Kaminari.config.param_name]
      @posts = blog_posts_scope.for_index(param_name).tagged_with(params[:tag])

      @page_title = "Blog Posts | #{params[:tag]}"
      render :index
    end

    def archives
      param_name = params[Kaminari.config.param_name]
      @posts = blog_posts_scope.for_index(param_name).by_month(params[:month], year: params[:year], field: :published_at)

      @page_title = "Blog Posts | #{Date.new(params[:year].to_i, params[:month].to_i).strftime('%B %Y')}"
      render :index
    end

    def new
      @post = current_blogger.blog_posts.new(post_paramters)
    end

    def edit
      @post = blog_posts_admin_scope.find(params[:id])
    end

    def create
      @post = current_blogger.blog_posts.new(post_paramters)
      if @post.save
        redirect_to @post, notice: t(:blog_post_was_successfully_created, scope: 'blogit.posts')
      else
        render action: "new"
      end
    end

    def update
      @post = blog_posts_admin_scope.find(params[:id])
      if @post.update_attributes(post_paramters)
        redirect_to @post, notice: t(:blog_post_was_successfully_updated, 
          scope: 'blogit.posts')
      else
        render action: "edit"
      end
    end

    def destroy
      @post = blog_posts_admin_scope.find(params[:id])
      @post.destroy
      redirect_to posts_url, notice: t(:blog_post_was_successfully_destroyed, scope: 'blogit.posts')
    end

    def post_paramters
      if params[:post]
        params.require(:post).permit(:title, :published_at, :body, :footnotes, :tag_list, :state)
      else
        {}
      end
    end

    private

    def blog_posts_admin_scope
      if blogit_conf.author_edits_only
        current_blogger.blog_posts
      else
        Post
      end
    end

    def blog_posts_scope
      if is_blogger_logged_in?
        Post
      else
        Post.active
      end
    end

    def load_sidebar_data
      @tags = ActsAsTaggableOn::Tag.all.where("taggings_count > 0")
      @posts_by_month = Post.active.group_by { |p| p.published_at.beginning_of_month }
      @recent_posts = Post.recent
    end

    def raise_404
      # Don't include admin actions if include_admin_actions is false
      render file: "#{Rails.root}/public/404.html", status: :not_found, layout: false
    end


    # @See the Pingr gem for more info https://github.com/KatanaCode/pingr
    def ping_search_engines
      case blogit_conf.ping_search_engines
      when Array
        search_engines = blogit_conf.ping_search_engines
      when true
        search_engines = Pingr::SUPPORTED_SEARCH_ENGINES
      end
      for search_engine in search_engines
        Pingr::Request.new(search_engine, posts_url(format: :xml)).ping
      end
    end

  end

end